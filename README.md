# Inkling

**A free, private Grammarly alternative for macOS.** Inkling checks your English as you type in any app, explains *why* each fix is right, and never sends a single word off your Mac.

- ✍️ **Works everywhere** — Mail, Notes, Messages, Slack, Chrome, Claude… any text field (via the macOS Accessibility API).
- ⚡ **Instant** — a native rule engine checks a paragraph in ~2 ms, so underlines appear as you type.
- 🎓 **Teaches, not just fixes** — every suggestion has a short lesson with ✗/✓ examples, plus a lesson library and progress stats.
- ✨ **On-device AI** — with Apple Intelligence on, Inkling also catches word order and unnatural phrasing, rewrites paragraphs DeepL-Write-style (Natural · Formal · Friendly · Concise), and explains any suggestion in plain words.
- 🔒 **100% local** — no account, no server, no telemetry. Text is held in memory only; the only thing saved is a count of mistake *types* for your progress chart.
- 🌍 **Stays out of your other language** — when you write in another language (currently tuned for Czech), Inkling simply disappears.

## How it works

| Layer | What it does |
|---|---|
| [`engine/`](engine) | Rust static library: [Harper](https://github.com/automattic/harper) grammar checker plus Inkling's own "coach" rules for common learner mistakes, behind a small C ABI. |
| [`App/Sources/Inkling/Core`](App/Sources/Inkling/Core) | Check pipeline (per-paragraph cache), language gate, preferences. |
| [`App/Sources/Inkling/Accessibility`](App/Sources/Inkling/Accessibility) | Follows focus across apps, measures text geometry, writes fixes back (with fallbacks for Electron/Chromium editors). |
| [`App/Sources/Inkling/Overlay`](App/Sources/Inkling/Overlay) | Underlines, badge, suggestion card, review list. |
| [`App/Sources/Inkling/Learning`](App/Sources/Inkling/Learning) | Lessons, spelling diagnosis, progress counts, on-device AI (FoundationModels). |
| [`App/Sources/Inkling/UI`](App/Sources/Inkling/UI) | Menu bar, settings, onboarding, theme. |

## Requirements

- macOS 26 (Tahoe) on Apple silicon
- Rust (the project pins its toolchain in `engine/rust-toolchain.toml`)
- Xcode Command Line Tools with the macOS 26 SDK
- Optional: Apple Intelligence enabled, for the AI features

## Build & run

```bash
scripts/build.sh            # → build/Inkling.app
scripts/build.sh --install  # also copies it to /Applications and launches it
```

The build script signs the app with the first Developer ID / Apple Development certificate it finds (or ad-hoc if there is none). On first launch, grant Inkling **Accessibility** access when asked — it needs it to read the field you're typing in and place underlines.

Engine tests:

```bash
cd engine && cargo test --release
```

## Privacy

Inkling has no networking code. It reads the focused text field through the Accessibility API, keeps the text in memory while you type and forgets it when you move on. Password fields are always skipped. AI features use Apple's on-device model only. Settings, your personal dictionary and per-day counts of mistake types are stored locally in `~/Library/Application Support/Inkling` and the app's preferences.

## Credits

Grammar checking is powered by [Harper](https://github.com/automattic/harper) (Apache-2.0) by Automattic.

## License

[MIT](LICENSE)
