import AppKit
import Carbon.HIToolbox
import DictationCore

@MainActor
final class HotKeyManager {
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    private var pressed = Set<UInt32>()
    var onAction: ((UInt32, Bool) -> Void)?
    init() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let action = id.id
            let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            Task { @MainActor in
                if down {
                    guard manager.pressed.insert(action).inserted else { return }
                } else {
                    guard manager.pressed.remove(action) != nil else { return }
                }
                manager.onAction?(action, down)
            }
            return noErr
        }, 2, &eventTypes, userData, &handler)
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
    func unregister() { references.forEach { UnregisterEventHotKey($0) }; references.removeAll(); pressed.removeAll() }
}
