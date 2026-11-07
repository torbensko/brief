import Combine
import DictationCore
import Foundation

/// The panel renders this small interface. Xcode uses an in-memory implementation,
/// so its real controls and views can be reviewed without app services or audio.
@MainActor protocol RecordingPresentation: ObservableObject {
    var batch: RecordingBatch { get }
    var sessions: [DictationSession] { get }
    var latestTranscript: DictationSession? { get }
    var settings: AppSettings { get }
    var message: String { get }
    var canStartRecording: Bool { get }
    var elapsed: Double { get }
    var levels: [Float] { get }
    var showHistory: (() -> Void)? { get }
    var showSettings: (() -> Void)? { get }
    var hideOverlay: (() -> Void)? { get }
    func toggleRecording()
    func stopAndKeepAudio()
    func cancelProcessing(_ id: UUID?)
    func skipCleanup(_ id: UUID?)
    func copyGroup()
    func copyCleanupOriginal(_ id: UUID?)
    func copy(_ session: DictationSession)
    func copyOriginal(_ session: DictationSession)
}

func duration(_ seconds: Double) -> String {
    let value = max(0, Int(seconds.isFinite ? seconds : 0))
    return String(format: "%d:%02d", value / 60, value % 60)
}
