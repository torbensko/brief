import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DictationCore

@MainActor
struct FocusTarget {
    let element: AXUIElement
    let window: AXUIElement?
    let pid: pid_t
    let application: String
    let bundleID: String
    let role: String
    let secure: Bool
    let editable: Bool
    let selection: CFRange?
    let valueFingerprint: Int?

    func matches(_ other: FocusTarget?) -> Bool {
        guard let other, pid == other.pid, CFEqual(element, other.element),
              secure == other.secure, selection?.location == other.selection?.location,
              selection?.length == other.selection?.length,
              valueFingerprint == other.valueFingerprint else { return false }
        if let a = window, let b = other.window { return CFEqual(a, b) }
        return window == nil && other.window == nil
    }
}

@MainActor
final class InsertionService {
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    private let terminalIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp",
        "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "org.alacritty", "co.zeit.hyper"
    ]
    func isTerminal(_ target: FocusTarget?) -> Bool {
        guard let target else { return false }; return terminalIDs.contains(target.bundleID)
    }
    func capture() -> FocusTarget? {
        guard Self.trusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        guard let raw = attribute(system, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.15)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier else { return nil }
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        let secure = subrole == "AXSecureTextField" || role == "AXSecureTextField"
        // Do not read any value from a secure field.
        let value = secure ? nil : attribute(element, kAXValueAttribute) as? String
        let enabled = (attribute(element, kAXEnabledAttribute) as? Bool) ?? true
        let editableFlag = attribute(element, "AXEditable") as? Bool
        var selection: CFRange?
        if !secure, let rawRange = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() {
            let rangeValue = unsafeBitCast(rawRange, to: AXValue.self)
            var range = CFRange()
            if AXValueGetValue(rangeValue, .cfRange, &range) { selection = range }
        }
        var window: AXUIElement?
        if let rawWindow = attribute(element, kAXWindowAttribute), CFGetTypeID(rawWindow) == AXUIElementGetTypeID() {
            window = unsafeBitCast(rawWindow, to: AXUIElement.self)
        }
        let editable = TextFieldEligibility.allows(role: role, enabled: enabled, editable: editableFlag, secure: secure)
        return FocusTarget(element: element, window: window, pid: pid,
            application: app.localizedName ?? "Application", bundleID: app.bundleIdentifier ?? "",
            role: role, secure: secure, editable: editable, selection: selection,
            valueFingerprint: value?.hashValue)
    }
    enum Method { case accessibility, paste }
    func method(for target: FocusTarget, allowPaste: Bool) throws -> Method {
        // Normal paste works with web editors whose AXSelectedText setter is unreliable.
        // Choose once, before any mutation; never retry a possibly partial insertion.
        if allowPaste { return .paste }
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(target.element, kAXSelectedTextAttribute as CFString, &settable)
        if result == .success && settable.boolValue { return .accessibility }
        throw DictationError.message("This field needs paste fallback. Enable it in Settings, or copy from History.")
    }
    func insert(_ text: String, into target: FocusTarget, method: Method) throws {
        // Re-check on the same main-actor turn as the actual side effect.
        guard target.matches(capture()), !target.secure, target.editable else {
            throw DictationError.message("Focus changed before insertion. The transcription is still pending.")
        }
        switch method {
        case .accessibility:
            let status = AXUIElementSetAttributeValue(target.element, kAXSelectedTextAttribute as CFString, text as CFString)
            guard status == .success else {
                // Do not follow a failed mutation with a second insertion: an application
                // could have partly handled the first request despite returning an error.
                throw DictationError.message("The target did not confirm insertion (Accessibility \(status.rawValue)). Check it before retrying; the text remains in History.")
            }
        case .paste:
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
                throw DictationError.message("Could not create the paste keyboard event.")
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                throw DictationError.message("Could not put the transcript on the clipboard.")
            }
            // Leave the transcript on the clipboard. Restoring it after an arbitrary
            // delay can race a slow application's paste and insert the wrong contents.
            down.flags = .maskCommand; up.flags = .maskCommand
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            // Deliberately no Return/Enter event.
        }
    }
    func expectedValue(for target: FocusTarget, text: String) -> String? {
        guard !target.secure, let selection = target.selection,
              let before = attribute(target.element, kAXValueAttribute) as? String else { return nil }
        return InsertionVerification.expectedValue(before: before, location: selection.location,
                                                   length: selection.length, text: text)
    }
    func verifyInsertion(into target: FocusTarget, expected: String?) async -> Bool {
        guard expected != nil else { return false }
        // Some editors apply paste asynchronously. Never insert a second time while checking.
        for _ in 0..<4 {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return false }
            guard let current = capture(), !current.secure, current.pid == target.pid,
                  CFEqual(current.element, target.element) else { return false }
            let actual = attribute(target.element, kAXValueAttribute) as? String
            if InsertionVerification.confirms(expected: expected, actual: actual) { return true }
        }
        return false
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
}
