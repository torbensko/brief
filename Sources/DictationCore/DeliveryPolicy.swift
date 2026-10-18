import Foundation

public struct DeliveryConditions: Sendable {
    public var automatic: Bool
    public var automaticEnabled: Bool
    public var trusted: Bool
    public var sameTarget: Bool
    public var focusChangedDuringRecording: Bool
    public var editable: Bool
    public var secure: Bool
    public var terminal: Bool
    public var allowTerminal: Bool
    public var requiresReview: Bool
    public init(automatic: Bool = true, automaticEnabled: Bool = true, trusted: Bool = true,
                sameTarget: Bool = true, focusChangedDuringRecording: Bool = false,
                editable: Bool = true, secure: Bool = false, terminal: Bool = false,
                allowTerminal: Bool = false, requiresReview: Bool = false) {
        self.automatic = automatic; self.automaticEnabled = automaticEnabled
        self.trusted = trusted; self.sameTarget = sameTarget
        self.focusChangedDuringRecording = focusChangedDuringRecording
        self.editable = editable; self.secure = secure; self.terminal = terminal
        self.allowTerminal = allowTerminal; self.requiresReview = requiresReview
    }
}
public enum DeliveryDecision: Equatable, Sendable {
    case insert
    case hold(String)
}
public enum DeliveryPolicy {
    public static func decide(_ c: DeliveryConditions) -> DeliveryDecision {
        if !c.trusted { return .hold("Accessibility permission is needed for insertion.") }
        if c.secure { return .hold("Secure fields are never insertion targets.") }
        if c.terminal && !c.allowTerminal { return .hold("Insertion into terminal applications is disabled.") }
        if !c.editable { return .hold("Select an editable text field, then use Insert Pending.") }
        if c.automatic {
            if !c.automaticEnabled { return .hold("Automatic insertion is disabled.") }
            if c.requiresReview { return .hold("Review this transcription before inserting it.") }
            if !c.sameTarget || c.focusChangedDuringRecording {
                return .hold("The destination changed. Select a field, then use Insert Pending.")
            }
        }
        return .insert
    }
}

/// Some browser editors expose a text role but omit AXSelectedTextRange.
/// Cursor-range availability is useful for change detection, not editability.
public enum TextFieldEligibility {
    public static func allows(role: String, enabled: Bool, editable: Bool?, secure: Bool) -> Bool {
        !secure && enabled && editable != false && ["AXTextField", "AXTextArea", "AXComboBox"].contains(role)
    }
}
