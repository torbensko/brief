import AppKit
import Carbon.HIToolbox
import DictationCore

@MainActor
final class HotKeyManager {
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    var onAction: ((UInt32) -> Void)?
    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let action = id.id
            Task { @MainActor in manager.onAction?(action) }
            return noErr
        }, 1, &eventType, userData, &handler)
    }
    func register(_ settings: AppSettings) throws {
        unregister()
        let bindings = [settings.recordShortcut, settings.insertShortcut, settings.historyShortcut]
        for (index, binding) in bindings.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x4C444943, id: UInt32(index + 1)) // LDIC
            let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                unregister()
                throw DictationError.message("Could not register \(binding.display) (status \(status)). Another app may be using it. Choose a different shortcut.")
            }
            references.append(ref)
        }
    }
    func unregister() { references.forEach { UnregisterEventHotKey($0) }; references.removeAll() }
}
