import AppKit
import Carbon.HIToolbox
import CaliperCore

/// Registers a system wide hotkey through Carbon.
///
/// RegisterEventHotKey is used rather than a CGEventTap or an NSEvent global monitor
/// because it requires no Accessibility permission. That is the whole reason Caliper
/// can arm itself on first launch without asking the user for anything.
final class HotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onFire: () -> Void

    /// Four character code "CLPR".
    private static let signature: OSType = 0x434C5052

    init(onFire: @escaping () -> Void) {
        self.onFire = onFire
    }

    func register(_ binding: HotKeyBinding) {
        unregister()

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue().onFire()
            return noErr
        }, 1, &spec, context, &eventHandler)

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(binding.keyCode,
                            Self.carbonModifiers(binding.modifiers),
                            identifier,
                            GetApplicationEventTarget(),
                            0,
                            &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    private static func carbonModifiers(_ modifiers: [ModifierKey]) -> UInt32 {
        var mask: UInt32 = 0
        for modifier in modifiers {
            switch modifier {
            case .control: mask |= UInt32(controlKey)
            case .option:  mask |= UInt32(optionKey)
            case .shift:   mask |= UInt32(shiftKey)
            case .command: mask |= UInt32(cmdKey)
            }
        }
        return mask
    }

    deinit {
        unregister()
    }
}
