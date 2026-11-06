import AppKit
import Carbon.HIToolbox

/// Registers one system-wide shortcut through Carbon, which works inside the App Sandbox
/// without Accessibility permission.
@MainActor
final class HotKeyService {
    static let shared = HotKeyService()

    var onPress: (() -> Void)?
    var hotKey: HotKey? { didSet { apply() } }
    /// Set while the settings recorder captures a new shortcut, so the current one reaches it.
    var isSuspended = false { didSet { apply() } }
    private(set) var registrationFailed = false

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    private func apply() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        registrationFailed = false
        guard let hotKey, !isSuspended else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x5457_5343), id: 1) // "TWSC"
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        registrationFailed = status != noErr
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in HotKeyService.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
