#if DEBUG
import AppKit
import DictationCore
import SwiftUI

// PreviewSupport/PreviewApp.swift provides the Xcode canvases for these fixtures.
// These previews render the production views. All actions affect only in-memory fixtures.
enum RecordingPreviewScenario: String, CaseIterable {
    case preparing = "Preparing"
    case recording = "Recording"
    case queued = "Queued"
    case transcribing = "Transcribing"
    case cleaning = "Clean up"
    case complete = "Complete"
    case stopped = "Audio only"
    case failed = "Error"
    case stacked = "Stacked recordings"

    var stages: [RecordingBatch.Stage] {
        switch self {
        case .preparing: return [.preparing]
        case .recording: return [.recording]
        case .queued: return [.queued]
        case .transcribing: return [.transcribing]
        case .cleaning: return [.cleaning]
        case .complete: return [.complete]
        case .stopped: return [.stopped]
        case .failed: return [.failed]
        case .stacked: return [.cleaning, .queued, .recording]
        }
    }
}

/// An actual-size comparison of the shared stage strip, for quick visual feedback.
@MainActor struct RecordingProgressPreview: View {
    @State private var dark: Bool
    init(dark: Bool = false) { _dark = State(initialValue: dark) }
    private let stages: [(String, RecordingBatch.Stage, Int?)] = [
        ("Recording", .recording, nil), ("Transcribing", .transcribing, nil),
        ("Cleaning up", .cleaning, nil), ("Complete", .complete, nil),
        ("Complete without cleanup", .complete, 1), ("Audio only or cancelled", .stopped, 1)
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Progress design").font(.headline)
                Spacer()
                Toggle("Dark", isOn: $dark).toggleStyle(.checkbox)
            }
            ForEach(stages, id: \.0) { title, stage, reached in
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    DictationProgress(stage: stage, reachedStep: reached)
                }
            }
        }.padding(28).frame(width: 360)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(dark ? .dark : .light)
    }
}

@MainActor struct RecordingPreviewPlayground: View {
    @StateObject private var model: RecordingPreviewModel
    @State private var panelHeight: CGFloat = 232
    @State private var dark: Bool

    init(scenario: RecordingPreviewScenario = .recording, dark: Bool = false) {
        _model = StateObject(wrappedValue: RecordingPreviewModel(scenario: scenario))
        _dark = State(initialValue: dark)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Brief UI preview").font(.title2.bold())
            HStack {
                Picker("Scenario", selection: Binding(get: { model.scenario }, set: { model.select($0) })) {
                    ForEach(RecordingPreviewScenario.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(width: 240)
                Button("Advance") { model.advance() }
                Button("Reset") { model.select(model.scenario) }
            }
            HStack(spacing: 18) {
                Toggle("Long text", isOn: Binding(get: { model.longText }, set: { model.setLongText($0) }))
                Toggle("Dark", isOn: $dark)
                Toggle("Permission notice", isOn: $model.settings.automaticInsertion)
            }.toggleStyle(.checkbox)
            Text("Preview controls above; actual app UI below. Buttons are simulated.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            ScrollView {
                RecordingOverlay(controller: model, appIcon: RecordingPreviewModel.icon,
                                 insertionPermissionGranted: false) { panelHeight = $0 }
                    .frame(width: 446, height: panelHeight, alignment: .top)
                    .animation(.easeInOut(duration: 0.25), value: panelHeight)
                    .padding(20).frame(maxWidth: .infinity, alignment: .top)
            }
            Text(model.lastAction).font(.caption).foregroundStyle(.secondary)
                .frame(height: 20, alignment: .leading)
        }.padding(24).frame(width: 680, height: 800)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(dark ? .dark : .light)
    }
}

@MainActor struct RecordingPreviewGallery: View {
    private let scenarios: [RecordingPreviewScenario] = [.preparing, .recording, .transcribing, .cleaning, .complete, .failed]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Brief • state comparison").font(.title2.bold())
                Text("The same production panel in each state. Use the Interactive review canvas to change text length or advance the flow.")
                    .font(.callout).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.fixed(446), alignment: .top), GridItem(.fixed(446), alignment: .top)],
                          alignment: .leading, spacing: 24) {
                    ForEach(scenarios, id: \.self) { RecordingPreviewCard(scenario: $0) }
                }
            }.padding(24)
        }.frame(width: 960, height: 900).background(Color(nsColor: .windowBackgroundColor))
    }
}

@MainActor private struct RecordingPreviewCard: View {
    let scenario: RecordingPreviewScenario
    @StateObject private var model: RecordingPreviewModel
    @State private var panelHeight: CGFloat = 232
    init(scenario: RecordingPreviewScenario) {
        self.scenario = scenario
        _model = StateObject(wrappedValue: RecordingPreviewModel(scenario: scenario))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scenario.rawValue).font(.headline)
            RecordingOverlay(controller: model, appIcon: RecordingPreviewModel.icon,
                             insertionPermissionGranted: false) { panelHeight = $0 }
                .frame(width: 446, height: panelHeight, alignment: .top)
        }
    }
}

/// No AppController, disk store, permission requests, clipboard, workers, or hotkeys.
@MainActor private final class RecordingPreviewModel: RecordingPresentation {
    @Published var batch = RecordingBatch()
    @Published var sessions: [DictationSession] = []
    @Published var settings: AppSettings = {
        var settings = AppSettings()
        settings.automaticInsertion = false
        return settings
    }()
    @Published var scenario: RecordingPreviewScenario
    @Published var longText = true
    @Published var lastAction = "Choose a state or click a control to review its appearance."
    let elapsed: Double = 13
    let levels: [Float] = (0..<28).map { 0.12 + Float(abs(sin(Double($0) * 0.63))) * 0.72 }
    private let fixtureIDs = [UUID(), UUID(), UUID()]
    var message: String { "Ready to record" }
    var latestTranscript: DictationSession? { sessions.last { $0.canInsert } }
    var canStartRecording: Bool { !batch.items.contains { [.preparing, .recording, .saving].contains($0.stage) } }
    var showHistory: (() -> Void)? { { [weak self] in self?.lastAction = "Recent selected (preview)." } }
    var showSettings: (() -> Void)? { { [weak self] in self?.lastAction = "Settings selected (preview)." } }
    var hideOverlay: (() -> Void)? { { [weak self] in self?.lastAction = "Close selected (preview). Reset keeps this panel available for feedback." } }
    static let icon = NSImage(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Brief.png"))

    init(scenario: RecordingPreviewScenario) {
        self.scenario = scenario
        select(scenario)
    }
    func select(_ scenario: RecordingPreviewScenario) {
        self.scenario = scenario
        batch = RecordingBatch(); sessions = []
        for index in scenario.stages.indices { batch.begin(fixtureIDs[index]) }
        for (index, stage) in scenario.stages.enumerated() { set(fixtureIDs[index], to: stage) }
        lastAction = "\(scenario.rawValue) • simulated data only."
    }
    func setLongText(_ value: Bool) {
        longText = value
        for item in batch.items { set(item.id, to: item.stage) }
    }
    func advance() {
        guard let item = batch.items.first(where: { $0.stage.isActive }) else { select(.preparing); return }
        switch item.stage {
        case .preparing: set(item.id, to: .recording)
        case .recording, .saving, .queued: set(item.id, to: .transcribing)
        case .transcribing: set(item.id, to: .cleaning)
        case .cleaning:
            set(item.id, to: .complete)
            if let next = batch.items.first(where: { $0.stage == .queued }) { set(next.id, to: .transcribing) }
        case .complete, .stopped, .failed: break
        }
        lastAction = "Advanced one stage."
    }
    func toggleRecording() {
        if let recording = batch.items.first(where: { $0.stage == .recording }) {
            let waiting = batch.items.contains { $0.id != recording.id && [.transcribing, .cleaning].contains($0.stage) }
            set(recording.id, to: waiting ? .queued : .transcribing)
            lastAction = "Stop selected. Use Advance to continue the simulated flow."
        } else {
            let id = UUID()
            batch.begin(id)
            set(id, to: .recording)
            lastAction = "Added a simulated recording."
        }
    }
    func stopAndKeepAudio() {
        guard let item = batch.items.first(where: { $0.stage == .recording }) else { return }
        batch.update(item.id, stage: .saving)
        batch.update(item.id, stage: .stopped, message: "Audio saved")
        lastAction = "Keep audio selected (preview)."
    }
    func cancelProcessing(_ id: UUID?) {
        guard let id else { return }
        batch.update(id, stage: .stopped, message: "Processing cancelled · audio saved")
        lastAction = "Cancelled this simulated recording."
    }
    func skipCleanup(_ id: UUID?) {
        guard let id else { return }
        set(id, to: .complete)
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].cleanup = nil
            batch.publish(sessions[index].text, for: id, chooseOriginal: true)
        }
        batch.update(id, message: "Original ready")
        lastAction = "Use original selected (preview)."
    }
    func copyGroup() { lastAction = "Copy all selected (preview; clipboard unchanged)." }
    func copyCleanupOriginal(_ id: UUID?) {
        guard let id, let session = sessions.first(where: { $0.id == id }) else { return }
        batch.publish(session.attempts.last?.text ?? "", for: id, chooseOriginal: true)
        batch.update(id, message: "Original copied · tidying continues")
        lastAction = "Copy original selected (preview; clipboard unchanged)."
    }
    func copy(_ session: DictationSession) {
        batch.update(session.id, message: "Copied to clipboard")
        lastAction = "Copy text selected (preview; clipboard unchanged)."
    }
    func copyOriginal(_ session: DictationSession) { lastAction = "Copy original selected (preview; clipboard unchanged)." }

    private func set(_ id: UUID, to stage: RecordingBatch.Stage) {
        let original = longText
            ? "The the preview should keep every recording in its own cell. Keep the stages at the top left while the timer and buttons stay on the right. A new recording can start while earlier audio is transcribing or cleaning up. Once the result is ready, the panel can expand smoothly to show the complete text."
            : "The the settings should keep every recording separate."
        var session = DictationSession(id: id, sampleRate: 16000, profileName: "Preview", vocabulary: "")
        var status = ""
        switch stage {
        case .cleaning, .complete:
            session.state = .ready
            session.attempts = [TranscriptAttempt(text: original, model: "Preview", vocabulary: "",
                processingSeconds: 0, audioSeconds: 13, generationTokens: 0)]
            if stage == .complete {
                session.cleanup = TranscriptCleanup(original: original,
                    text: original.replacingOccurrences(of: "The the", with: "The"), model: "Preview")
            }
            status = stage == .cleaning ? "Tidying wording · original on clipboard" : "Copied to clipboard · press ⌘V to paste"
            batch.publish(session.text, for: id)
        case .failed:
            session.state = .failed
            status = "Transcription stopped. Your recording is saved for retry."
        case .queued, .saving: session.state = .captured
        case .stopped:
            session.state = .captured
            status = "Audio saved"
            batch.update(id, stage: .saving)
        case .transcribing: session.state = .transcribing
        case .preparing, .recording: session.state = .recording
        }
        if let index = sessions.firstIndex(where: { $0.id == id }) { sessions[index] = session }
        else { sessions.append(session) }
        batch.update(id, stage: stage, message: status)
    }
}
#endif
