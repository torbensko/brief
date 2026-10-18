/// Tracks ownership so a release cannot stop a recording started by another control,
/// or start recording after a press that was ignored while recognition was busy.
public struct RecordingGesture: Sendable {
    public enum Action: Equatable, Sendable { case none, start, stop, cancelPreparation, toggle }
    public private(set) var ownsRecording = false
    private var pressed = false
    public init() {}
    public mutating func handle(down: Bool, mode: RecordingMode, idle: Bool, preparing: Bool, recording: Bool) -> Action {
        if down {
            guard !pressed else { return .none }
            pressed = true
            guard mode == .hold, idle else { return .none }
            ownsRecording = true
            return .start
        }
        guard pressed else { return .none }
        pressed = false
        if mode == .toggle { return .toggle }
        guard ownsRecording else { return .none }
        ownsRecording = false
        if preparing { return .cancelPreparation }
        return recording ? .stop : .none
    }
}
