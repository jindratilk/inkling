import Carbon
import Foundation

/// Minimal global hotkey (no key logging — macOS only tells us when *this* combo is pressed).
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    private let action: () -> Void

    private static var registry: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        let id = Self.nextID
        Self.nextID += 1
        Self.registry[id] = self

        if Self.handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if let target = HotKey.registry[hk.id] {
                DispatchQueue.main.async { target.action() }
            }
            return noErr
        }, 1, &spec, nil, &Self.handler)
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x494E_4B4C), id: id) // 'INKL'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }
}
