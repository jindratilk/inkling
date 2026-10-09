import AppKit
import Combine
import NaturalLanguage
import SwiftUI

/// Orchestrates everything you see on top of other apps: underlines, the
/// badge, the suggestion card and the review list.
@MainActor
final class OverlayController: FocusTrackerDelegate {
    private let pipeline: CheckPipeline
    private let prefs = Preferences.shared
    private let progress = ProgressStore.shared
    private let state = AppState.shared

    private let underlinePanel = ClickThroughPanel()
    private let underlineModel = UnderlineModel()
    private let badgePanel = FloatingPanel(level: .statusBar)
    private let badgeModel = BadgeModel()
    private let cardPanel = FloatingPanel()
    private let reviewPanel = FloatingPanel()
    private let reviewModel = ReviewModel()
    private let ai = AIProofreader()
    private var aiWork: DispatchWorkItem?
    private var improveTask: Task<Void, Never>?
    private var improveRefresh: DispatchWorkItem?

    private(set) var field: TrackedField?
    private var lints: [Lint] = []
    private var language: DocLanguage = .undetermined
    private var token = 0
    private var lastCheckStart = Date.distantPast
    private var lastEdit = Date.distantPast
    private var dismissed = Set<String>()
    private var seen = Set<String>()
    private var clip: CGRect?
    private var rectsByLint: [UUID: [CGRect]] = [:]
    private var cardLintID: UUID?
    private var reviewOpen = false
    private var lastMicros = 0

    private var checkWork: DispatchWorkItem?
    private var hoverWork: DispatchWorkItem?
    private var hideCardWork: DispatchWorkItem?
    private var scrollWork: DispatchWorkItem?
    private var monitors: [Any] = []
    private var geometryTimer: Timer?
    private var bag = Set<AnyCancellable>()

    init(pipeline: CheckPipeline) {
        self.pipeline = pipeline

        underlinePanel.contentView = NSHostingView(rootView: UnderlineCanvas(model: underlineModel))

        let badgeHost = FirstMouseHostingView(rootView: BadgeView(model: badgeModel) { [weak self] in self?.toggleReview() })
        badgeHost.frame = NSRect(x: 0, y: 0, width: BadgeView.window, height: BadgeView.window)
        badgePanel.contentView = badgeHost
        badgePanel.setContentSize(NSSize(width: BadgeView.window, height: BadgeView.window))
        badgePanel.margin = (BadgeView.window - 26) / 2
        cardPanel.margin = Ink.shadowPad - 2
        reviewPanel.margin = Ink.shadowPad - 2

        reviewPanel.host(ReviewListView(model: reviewModel, actions: reviewActions))

        installMonitors()

        ai.onResult = { [weak self] in self?.scheduleCheck(after: 0) }
        ai.onBusyChange = { [weak self] busy in self?.badgeModel.thinking = busy }

        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.periodicRefresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        geometryTimer = timer

        // Settings that change what we show take effect immediately.
        prefs.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] in self?.preferencesChanged() }
            .store(in: &bag)
    }

    // MARK: - FocusTrackerDelegate

    func trackerDidChangeField(_ newField: TrackedField?) {
        hideCard(animated: false)
        closeReview()
        aiWork?.cancel()
        ai.cancelPending()
        field = newField
        lints = []
        language = .undetermined
        seen.removeAll()
        token += 1
        clip = nil
        underlineModel.items = []

        state.hasField = newField != nil
        if let newField {
            state.appName = newField.appName
            state.bundleID = newField.bundleID
            state.appIcon = newField.appIcon
        } else if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            state.appName = front.localizedName
            state.bundleID = front.bundleIdentifier
            state.appIcon = front.icon
        }
        state.issueCount = 0
        state.language = .undetermined

        guard let newField, shouldRun(newField) else {
            hideOverlays()
            return
        }
        scheduleCheck(after: 0)
    }

    func trackerTextDidChange(_ changed: TrackedField, from oldText: String) {
        guard changed === field else { return }
        lastEdit = Date()
        lints = lints.remapped(from: oldText, to: changed.text)
        hideCard(animated: true)
        render()
        // Check quickly after a pause, but never let continuous typing starve the checker.
        let sinceLast = Date().timeIntervalSince(lastCheckStart)
        scheduleCheck(after: sinceLast > 0.8 ? 0.02 : 0.14)
    }

    func trackerSelectionDidChange(_ changed: TrackedField) {
        guard changed === field else { return }
        render()
    }

    func trackerGeometryDidChange() {
        render()
    }

    // MARK: - Checking

    private func shouldRun(_ f: TrackedField) -> Bool {
        state.trusted && prefs.isActive && !prefs.isExcluded(f.bundleID)
    }

    private func scheduleCheck(after delay: TimeInterval) {
        checkWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.runCheck() }
        checkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func runCheck() {
        guard let field, shouldRun(field) else { return }
        token += 1
        let myToken = token
        lastCheckStart = Date()
        pipeline.submit(text: field.text, focus: field.element.visibleCharacterRange, token: myToken) { [weak self] outcome in
            MainActor.assumeIsolated { self?.receive(outcome) }
        }
    }

    private func receive(_ outcome: CheckOutcome) {
        guard let field, outcome.token == token else { return }
        language = outcome.language
        lastMicros = outcome.micros
        state.lastCheckMicros = outcome.micros
        state.language = language

        var fresh = outcome.lints.filter { prefs.allows($0.category) && !prefs.disabledRules.contains($0.rule) }
        if outcome.text != field.text {
            fresh = fresh.remapped(from: outcome.text, to: field.text)
        }
        let text = field.text
        fresh = fresh.filter { !dismissed.contains($0.dismissalKey(in: text)) }

        // On-device AI: grammar & fluency the rules can't see.
        if prefs.aiSuggestions, AIProofreader.isAvailable, language == .english {
            let (aiLints, missing, better) = ai.lints(for: text, avoiding: fresh)
            if !better.isEmpty {
                fresh = fresh.map { lint in
                    guard let s = better[lint.uid] else { return lint }
                    var l = lint
                    l.suggestions = [s] + l.suggestions.filter { $0 != s }
                    return l
                }
            }
            fresh += aiLints.filter {
                prefs.allows($0.category) && !prefs.disabledRules.contains($0.rule) && !dismissed.contains($0.dismissalKey(in: text))
            }
            scheduleAI(missing)
        }

        // Keep identities stable so underlines glide rather than redraw.
        var previous: [String: UUID] = [:]
        for l in lints { previous["\(l.rule)|\(l.start)|\(l.original)"] = l.uid }
        var used = Set<UUID>()
        fresh = fresh.map { lint in
            var l = lint
            if let uid = previous["\(l.rule)|\(l.start)|\(l.original)"], !used.contains(uid) {
                l.uid = uid
            } else if used.contains(l.uid) {
                l.uid = UUID()
            }
            used.insert(l.uid)
            return l
        }
        let hadCount = lints.count
        lints = fresh.sorted { ($0.start, $0.end) < ($1.start, $1.end) }

        for l in lints where seen.insert("\(l.rule)|\(l.original)").inserted {
            progress.recordSeen(l)
        }
        if lints.count > hadCount { badgeModel.pulse += 1 }
        render()
    }

    /// Ask the AI only once typing has paused, so it never competes with you.
    private func scheduleAI(_ sentences: [String]) {
        aiWork?.cancel()
        guard !sentences.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if Date().timeIntervalSince(self.lastEdit) < 0.8 {
                self.scheduleAI(sentences)
                return
            }
            self.ai.enqueue(sentences)
        }
        aiWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func preferencesChanged() {
        guard let field else { return }
        if !shouldRun(field) {
            hideOverlays()
            state.issueCount = 0
            return
        }
        lints = lints.filter { prefs.allows($0.category) && !prefs.disabledRules.contains($0.rule) }
        render()
        scheduleCheck(after: 0.35) // engine may have been rebuilt
    }

    // MARK: - Rendering

    /// Lints worth drawing right now. We hold back the word you're still typing.
    private func displayLints() -> [Lint] {
        guard let field, let caret = field.selection, caret.length == 0,
              Date().timeIntervalSince(lastEdit) < 3 else { return lints }
        return lints.filter { l in
            !(l.end == caret.location || (l.start < caret.location && caret.location < l.end))
        }
    }

    private func render() {
        guard let field, shouldRun(field), language == .english else {
            hideOverlays()
            updateState()
            return
        }
        guard let visible = field.visibleFrame() else {
            hideOverlays()
            return
        }

        let frameChanged = clip.map { !$0.equalTo(visible) } ?? true
        clip = visible
        let panelFrame = visible.insetBy(dx: -6, dy: -6)
        if frameChanged { underlinePanel.setFrame(panelFrame, display: false) }

        let shown = displayLints()
        let visibleRange = field.element.visibleCharacterRange
        var items: [UnderlineModel.Item] = []
        var rects: [UUID: [CGRect]] = [:]
        var budget = 160

        for l in shown {
            if let vr = visibleRange, vr.length > 0, NSIntersectionRange(vr, l.range).length == 0, l.range.length > 0 { continue }
            guard budget > 0 else { break }
            budget -= 1
            var r = field.rects(for: l.range).filter { $0.intersects(visible.insetBy(dx: -2, dy: -2)) && $0.width > 0.5 }
            if r.isEmpty, l.range.length == 0 { continue }
            r = r.map { $0.intersection(visible.insetBy(dx: -3, dy: -3)) }.filter { !$0.isNull && $0.width > 0.5 }
            guard !r.isEmpty else { continue }
            rects[l.uid] = r
            let local = r.map { CGRect(x: $0.minX - panelFrame.minX, y: panelFrame.maxY - $0.maxY, width: $0.width, height: $0.height) }
            items.append(.init(id: l.uid, rects: local, category: l.category, hint: l.isHint))
        }
        rectsByLint = rects

        if items != underlineModel.items {
            if frameChanged {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { underlineModel.items = items }
            } else {
                withAnimation(.easeOut(duration: 0.18)) { underlineModel.items = items }
            }
        }
        if !underlinePanel.isVisible { underlinePanel.orderFrontRegardless() }

        updateBadge(in: visible, field: field)
        updateState()
        if reviewOpen { refreshReview() }
    }

    private func updateBadge(in visible: CGRect, field: TrackedField) {
        guard prefs.showBadge else {
            badgePanel.orderOut(nil)
            return
        }
        let top = lints.min { $0.category.importance < $1.category.importance }?.category ?? .spelling
        if badgeModel.category != top { badgeModel.category = top }
        if badgeModel.count != lints.count { badgeModel.count = lints.count }

        let size = BadgeView.window
        // Centre of the 22pt orb, tucked into the field's corner.
        let center: CGPoint
        if field.isSingleLine || visible.height < 46 {
            center = CGPoint(x: visible.maxX - 14, y: visible.midY)
        } else {
            center = CGPoint(x: visible.maxX - 19, y: visible.minY + 19)
        }
        let origin = CGPoint(x: center.x - size / 2, y: center.y - size / 2)
        let frame = NSRect(origin: origin, size: NSSize(width: size, height: size))
        if !badgePanel.frame.equalTo(frame) { badgePanel.setFrame(frame, display: true) }
        if !badgePanel.isVisible { badgePanel.orderFrontRegardless() }
    }

    private func updateState() {
        let count = (language == .english) ? lints.count : 0
        if state.issueCount != count { state.issueCount = count }
        var counts: [IssueCategory: Int] = [:]
        lints.forEach { counts[$0.category, default: 0] += 1 }
        if state.categoryCounts != counts { state.categoryCounts = counts }
    }

    private func hideOverlays() {
        if !underlineModel.items.isEmpty { underlineModel.items = [] }
        rectsByLint = [:]
        underlinePanel.orderOut(nil)
        badgePanel.orderOut(nil)
        hideCard(animated: false)
        closeReview()
    }

    private func periodicRefresh() {
        guard field != nil, underlinePanel.isVisible || badgePanel.isVisible else { return }
        // Catch layout changes apps don't announce (live resize, reflow, scroll inertia…).
        render()
    }

    // MARK: - Mouse

    private func installMonitors() {
        let moved = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved(NSEvent.mouseLocation) }
        }
        let scrolled = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrolled() }
        }
        let clicked = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedElsewhere(NSEvent.mouseLocation) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved(NSEvent.mouseLocation) }
            return event
        }
        monitors = [moved, scrolled, clicked, local].compactMap { $0 }
    }

    private func hitTest(_ p: CGPoint) -> UUID? {
        for (uid, rects) in rectsByLint where rects.contains(where: { $0.insetBy(dx: -1, dy: -3).contains(p) }) {
            return uid
        }
        return nil
    }

    private func mouseMoved(_ p: CGPoint) {
        cardPanel.updatePassthrough(p)
        reviewPanel.updatePassthrough(p)
        badgePanel.updatePassthrough(p)
        if cardPanel.isVisible, cardPanel.frame.insetBy(dx: Ink.shadowPad - 12, dy: Ink.shadowPad - 12).contains(p) {
            hideCardWork?.cancel()
            return
        }
        if reviewOpen, reviewPanel.contentRect.contains(p) { return }

        if let uid = hitTest(p) {
            hideCardWork?.cancel()
            if underlineModel.hovered != uid, cardLintID == nil { underlineModel.hovered = uid }
            guard cardLintID != uid else { return }
            hoverWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.showCard(for: uid) }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (cardLintID == nil ? 0.11 : 0.05), execute: work)
        } else {
            hoverWork?.cancel()
            if cardLintID == nil, underlineModel.hovered != nil, !reviewOpen { underlineModel.hovered = nil }
            if cardPanel.isVisible, hideCardWork == nil || hideCardWork!.isCancelled {
                let work = DispatchWorkItem { [weak self] in self?.hideCard(animated: true) }
                hideCardWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: work)
            }
        }
    }

    private func scrolled() {
        guard let clip, clip.contains(NSEvent.mouseLocation), !underlineModel.items.isEmpty else { return }
        if reviewOpen, reviewPanel.contentRect.contains(NSEvent.mouseLocation) { return }
        underlineModel.visible = false
        hideCard(animated: true)
        scrollWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.render()
            self.underlineModel.visible = true
        }
        scrollWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    private func clickedElsewhere(_ p: CGPoint) {
        if reviewOpen, !reviewPanel.contentRect.contains(p), !badgePanel.contentRect.contains(p) { closeReview() }
        if cardPanel.isVisible, !cardPanel.contentRect.contains(p) {
            if let uid = hitTest(p) {
                showCard(for: uid)
            } else {
                hideCard(animated: true)
            }
        }
    }

    // MARK: - Card

    private func showCard(for uid: UUID) {
        guard let field, let lint = lints.first(where: { $0.uid == uid }), let rects = rectsByLint[uid], let first = rects.first else { return }
        hideCardWork?.cancel()
        cardLintID = uid
        underlineModel.hovered = uid

        let view = SuggestionCardView(lint: lint, sentence: sentence(around: lint, in: field.text), actions: cardActions(for: lint))
        let size = NSHostingView(rootView: view.fixedSize()).fittingSize

        let screen = NSScreen.screens.first { $0.frame.contains(first.origin) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .infinite
        let inset = Ink.shadowPad // shadow padding baked into the view
        let x = min(max(first.minX - inset - 12, vf.minX + 4), vf.maxX - size.width - 4)
        let last = rects.last ?? first
        let needed = size.height - inset * 2 + 8
        let below = first.minY - vf.minY
        let above = vf.maxY - last.maxY
        if below >= needed || below >= above {
            cardPanel.anchor = .top(first.minY - 4 + inset)
        } else {
            cardPanel.anchor = .bottom(last.maxY + 4 - inset)
        }
        cardPanel.limits = vf.insetBy(dx: 0, dy: -inset)
        cardPanel.anchorX = x
        cardPanel.setFrame(NSRect(origin: .zero, size: size), display: false)
        cardPanel.host(view)
        cardPanel.alphaValue = 1
        cardPanel.orderFrontRegardless()
        cardPanel.updatePassthrough(NSEvent.mouseLocation)
    }

    private func hideCard(animated: Bool) {
        hoverWork?.cancel()
        hideCardWork?.cancel()
        hideCardWork = nil
        cardLintID = nil
        if !reviewOpen { underlineModel.hovered = nil }
        if animated { cardPanel.fadeOut() } else { cardPanel.orderOut(nil) }
    }

    private func cardActions(for lint: Lint) -> CardActions {
        CardActions(
            accept: { [weak self] s in self?.accept(lint, with: s) },
            dismiss: { [weak self] in self?.dismiss(lint) },
            ignoreRule: { [weak self] in self?.ignoreRule(of: lint) },
            addToDictionary: lint.isSpelling ? { [weak self] in self?.addToDictionary(lint) } : nil
        )
    }

    private func sentence(around lint: Lint, in text: String) -> String {
        let ns = text as NSString
        guard NSMaxRange(lint.range) <= ns.length else { return lint.original }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        guard let idx = Range(NSRange(location: lint.start, length: 0), in: text)?.lowerBound else { return lint.original }
        let r = tokenizer.tokenRange(at: idx)
        let s = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(s.prefix(600))
    }

    // MARK: - Actions

    private func accept(_ lint: Lint, with replacement: String, refresh: Bool = true) {
        guard let field else { return }
        let flashRects = underlineModel.items.first { $0.id == lint.uid }?.rects ?? []
        switch TextApplier.apply(replacement, for: lint, in: field) {
        case .applied:
            progress.recordFixed(lint)
            if !flashRects.isEmpty {
                let flash = UnderlineModel.Flash(rects: flashRects, color: lint.category.color)
                underlineModel.flashes.append(flash)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.underlineModel.flashes.removeAll { $0.id == flash.id }
                }
            }
            withAnimation(.easeOut(duration: 0.15)) {
                lints.removeAll { $0.uid == lint.uid }
            }
            if let now = field.element.value, now != field.text {
                let old = field.text
                field.text = now
                lints = lints.remapped(from: old, to: now)
            }
            if refresh {
                hideCard(animated: true)
                render()
                scheduleCheck(after: 0.05)
            }
        case .stale:
            hideCard(animated: true)
            scheduleCheck(after: 0)
        case .failed:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(replacement, forType: .string)
            NSSound.beep()
            hideCard(animated: true)
        }
    }

    private func dismiss(_ lint: Lint) {
        guard let field else { return }
        dismissed.insert(lint.dismissalKey(in: field.text))
        progress.recordDismissed(lint)
        lints.removeAll { $0.uid == lint.uid }
        hideCard(animated: true)
        render()
    }

    private func ignoreRule(of lint: Lint) {
        prefs.disableRule(lint.rule)
        lints.removeAll { $0.rule == lint.rule }
        hideCard(animated: true)
        render()
    }

    private func addToDictionary(_ lint: Lint) {
        prefs.addWord(lint.original)
        lints.removeAll { $0.isSpelling && $0.original.lowercased() == lint.original.lowercased() }
        hideCard(animated: true)
        render()
    }

    // MARK: - Review list

    private var reviewActions: ReviewActions {
        ReviewActions(
            accept: { [weak self] lint, s in self?.accept(lint, with: s) },
            dismiss: { [weak self] lint in self?.dismiss(lint) },
            hover: { [weak self] uid in self?.underlineModel.hovered = uid },
            fixAll: { [weak self] list in self?.fixAll(list) },
            close: { [weak self] in self?.closeReview() },
            improve: { [weak self] tone in self?.runImprove(tone) },
            applyImprove: { [weak self] in self?.applyImprove() }
        )
    }

    func toggleReview() {
        reviewOpen ? closeReview() : openReview()
    }

    func openReview() {
        guard field != nil, language == .english, badgePanel.isVisible else { return }
        hideCard(animated: false)
        reviewOpen = true
        badgeModel.reviewOpen = true
        refreshReview()
        if AIProofreader.isAvailable { runImprove(reviewModel.tone) }
        reviewPanel.alphaValue = 1
        positionReview()
        reviewPanel.orderFrontRegardless()
        reviewPanel.updatePassthrough(NSEvent.mouseLocation)
        // SwiftUI resizes the panel on the next layout pass; re-pin after it.
        DispatchQueue.main.async { [weak self] in self?.positionReview() }
    }

    // MARK: - Improve (DeepL Write–style)

    private var improveRange: NSRange?

    /// The text to rewrite: the whole field when it's short, otherwise the paragraph you're in.
    private func improveTarget(in text: String, caret: Int?) -> NSRange? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        var r: NSRange
        if ns.length <= 1500 {
            r = NSRange(location: 0, length: ns.length)
        } else {
            let loc = min(max(0, caret ?? 0), ns.length - 1)
            r = ns.paragraphRange(for: NSRange(location: loc, length: 0))
        }
        // trim surrounding whitespace / newlines
        let ws = CharacterSet.whitespacesAndNewlines
        func isWS(_ i: Int) -> Bool { Unicode.Scalar(UInt32(ns.character(at: i))).map { ws.contains($0) } ?? false }
        while r.length > 0, isWS(r.location) { r.location += 1; r.length -= 1 }
        while r.length > 0, isWS(NSMaxRange(r) - 1) { r.length -= 1 }
        return r.length > 0 ? r : nil
    }

    private func runImprove(_ tone: WritingTone) {
        guard let field, let range = improveTarget(in: field.text, caret: field.selection?.location) else { return }
        let source = (field.text as NSString).substring(with: range)
        improveRange = range
        improveTask?.cancel()
        reviewModel.improveSource = source
        reviewModel.improved = nil
        reviewModel.improveFailed = false
        reviewModel.improving = true
        improveTask = Task { [weak self] in
            let out = await AIImprover.improve(source, tone: tone)
            guard let self, !Task.isCancelled else { return }
            self.reviewModel.improving = false
            if let out { self.reviewModel.improved = out } else { self.reviewModel.improveFailed = true }
        }
    }

    private func applyImprove() {
        guard let range = improveRange, let improved = reviewModel.improved else { return }
        let lint = Lint(rule: "AI.Improve", kind: "Style", start: range.location, end: NSMaxRange(range),
                        original: reviewModel.improveSource, message: "", priority: 0, suggestions: [improved],
                        description: "", lesson: nil, severity: "hint")
        accept(lint, with: improved)
        reviewModel.improved = nil
        reviewModel.improveSource = ""
    }

    func closeReview() {
        guard reviewOpen else { return }
        reviewOpen = false
        badgeModel.reviewOpen = false
        underlineModel.hovered = nil
        reviewPanel.fadeOut()
        improveTask?.cancel()
        reviewModel.improved = nil
        reviewModel.improving = false
    }

    private func refreshReview() {
        let next = lints
        if reviewModel.lints.map(\.id) != next.map(\.id) || reviewModel.lints != next {
            withAnimation(Ink.spring) { reviewModel.lints = next }
        }
        reviewModel.micros = lastMicros
        reviewModel.aiAvailable = AIProofreader.isAvailable
        // Keep the "Better version" in step with the text (e.g. after accepting a fix).
        if AIProofreader.isAvailable, let f = field, let r = improveTarget(in: f.text, caret: f.selection?.location) {
            let source = (f.text as NSString).substring(with: r)
            if source != reviewModel.improveSource, !reviewModel.improving {
                improveRefresh?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.reviewOpen else { return }
                    self.runImprove(self.reviewModel.tone)
                }
                improveRefresh = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
            }
        }
        positionReview()
    }

    private func positionReview() {
        guard reviewOpen else { return }
        let badge = badgePanel.frame
        let size = reviewPanel.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(badge) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .infinite
        let inset = Ink.shadowPad
        let x = min(max(badge.maxX - size.width + inset - 4, vf.minX + 4), vf.maxX - size.width + inset)
        if badge.maxY + size.height - inset < vf.maxY {
            reviewPanel.anchor = .bottom(badge.maxY + 2 - inset)
        } else {
            reviewPanel.anchor = .top(badge.minY - 2 + inset)
        }
        reviewPanel.anchorX = x
        reviewPanel.limits = vf.insetBy(dx: 0, dy: -inset)
        reviewPanel.setFrame(reviewPanel.frame, display: true)
    }

    private func fixAll(_ list: [Lint]) {
        // From the end backwards so earlier offsets stay valid.
        for lint in list.sorted(by: { $0.start > $1.start }) {
            guard let current = lints.first(where: { $0.uid == lint.uid }), let s = current.suggestions.first else { continue }
            accept(current, with: s, refresh: false)
        }
        render()
        scheduleCheck(after: 0.05)
    }
}
