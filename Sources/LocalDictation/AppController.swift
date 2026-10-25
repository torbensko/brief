import AppKit
import AVFoundation
import Combine
import DictationCore

@MainActor
final class AppController: ObservableObject {
    enum Phase: String { case idle, preparing, recording, stopping, transcribing, loading, downloading }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var sessions: [DictationSession] = []
    @Published private(set) var settings: AppSettings
    @Published var message = "Ready to record"
    @Published var errorMessage: String?
    @Published private(set) var noSpeechDetected = false
    @Published private(set) var tidyingWording = false
    private var cleanupSkipped = false
    @Published private(set) var deliveryConfirmed = false
    @Published private(set) var historyWarnings: [String] = []
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var levels = [Float](repeating: 0.03, count: 28)
    @Published private(set) var modelLoaded = false
    @Published var selectedSessionID: UUID?
    @Published private(set) var downloadMessage = ""
    @Published private(set) var scanningRepositories = false
    @Published private(set) var repositoryScanMessage = ""
    private var repositoryScanTask: Task<Void, Never>?
    var showHistory: (() -> Void)?
    var showSettings: (() -> Void)?
    var showOverlay: (() -> Void)?
    var hideOverlay: (() -> Void)?
    var fadeOverlay: (() -> Void)?
    var settingsDidChange: (() -> Void)?
    let root: URL
    let store: HistoryStore
    let hotKeys = HotKeyManager()
    private let settingsURL: URL
    private let worker = WorkerClient()
    private let cleanupWorker = WorkerClient()
    private let recorder = AudioRecorder()
    private let insertion = InsertionService()
    private let installer = ModelInstaller()
    private var operationTask: Task<Void, Never>?
    private var overlayDismissTask: Task<Void, Never>?
    private var recoveryTimer: Timer?
    private var ticker: Timer?
    var latestTranscript: DictationSession? { sessions.first { $0.canInsert } }
    private var recordingGesture = RecordingGesture()
    private var releasedDuringPreparation = false
    private var tickCount = 0
    private var target: FocusTarget?
    private var focusChanged = false
    private var activeSessionID: UUID?
    private var stagedSessionID: UUID?
    private var player: AVAudioPlayer?
    private var activity: NSObjectProtocol?
    var isBusy: Bool { phase != .idle }
    var pendingSession: DictationSession? {
        if let id = stagedSessionID, let value = sessions.first(where: { $0.id == id && $0.canInsert && $0.delivery == .pending }) {
            return value
        }
        return sessions.first { $0.canInsert && $0.delivery == .pending }
    }
    var modelAvailable: Bool {
        !settings.modelDirectory.isEmpty && FileManager.default.fileExists(atPath: settings.modelDirectory)
    }

    init(storageRoot: URL? = nil) throws {
        root = try storageRoot ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true).appendingPathComponent("LocalDictation", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        settingsURL = root.appendingPathComponent("settings.json")
        settings = try SettingsFile.load(from: settingsURL)
        store = try HistoryStore(root: root.appendingPathComponent("Sessions", isDirectory: true))
        worker.onExit = { [weak self] in self?.modelLoaded = false }
        hotKeys.onAction = { [weak self] id, down in
            switch id {
            case 1: self?.recordShortcut(down: down)
            case 2: if !down { self?.insertPending() }
            case 3: if !down { self?.showHistory?() }
            default: break
            }
        }
    }
    func bootstrap() async {
        await refreshHistory(recover: true)
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isBusy else { return }
                await self.refreshHistory()
            }
        }
        scanRepositories(path: settings.effectiveRepositoriesPath)
        do { try hotKeys.register(settings) } catch { report(error) }
        if modelAvailable { warmModel() }
        else { showSettings?() }
    }
    func refreshHistory(recover: Bool = false) async {
        do {
            _ = try await store.snapshot(recoverInterrupted: recover)
            if !isBusy {
                // Do not displace the last usable transcript merely because a newer attempt failed.
                let before = try await store.snapshot()
                let protected: Set<UUID> = settings.effectiveRecoveryPolicy.mode == .count
                    ? Set(before.sessions.first(where: { $0.canInsert }).map { [$0.id] } ?? []) : []
                try await store.prune(settings.effectiveRecoveryPolicy, protecting: protected)
            }
            let snapshot = try await store.snapshot()
            if sessions.contains(where: { old in !snapshot.sessions.contains(where: { $0.id == old.id }) }) { stopPlayback() }
            sessions = snapshot.sessions; historyWarnings = snapshot.warnings
            if selectedSessionID == nil || !sessions.contains(where: { $0.id == selectedSessionID }) {
                selectedSessionID = latestTranscript?.id ?? sessions.first?.id
            }
            if sessions.isEmpty && !isBusy { hideOverlay?() }
        } catch { report(error) }
    }
    func apply(_ updated: AppSettings) throws {
        guard !isBusy else { throw DictationError.message("Finish the current operation before changing settings.") }
        try updated.validate()
        do { try hotKeys.register(updated); try SettingsFile.save(updated, to: settingsURL) }
        catch {
            // Restore the previous shortcut registrations if validation/registration/save failed.
            try? hotKeys.register(settings)
            throw error
        }
        if updated.modelDirectory != settings.modelDirectory { worker.stop(); modelLoaded = false }
        settings = updated
        settingsDidChange?()
        errorMessage = nil
        Task { await refreshHistory() }
    }
    private func recordShortcut(down: Bool) {
        let action = recordingGesture.handle(down: down, mode: settings.effectiveRecordingMode,
            idle: phase == .idle, preparing: phase == .preparing, recording: phase == .recording)
        switch action {
        case .start, .stop, .toggle: toggleRecording()
        case .cancelPreparation: releasedDuringPreparation = true
        case .none: break
        }
    }
    var recordingFinishHint: String {
        recordingGesture.ownsRecording ? "Release \(settings.recordShortcut.display) to finish" :
            (settings.effectiveRecordingMode == .toggle ? "\(settings.recordShortcut.display) to finish" : "Use Stop to finish")
    }
    func toggleRecording() {
        overlayDismissTask?.cancel()
        switch phase {
        case .idle:
            releasedDuringPreparation = false
            phase = .preparing
            target = insertion.capture()
            focusChanged = target == nil
            operationTask = Task { await startRecording() }
        case .recording:
            phase = .stopping
            operationTask = Task { await finishRecording(transcribe: true) }
        default:
            message = "Finish or cancel the current operation first. Saved recordings remain in History."
            showOverlay?()
        }
    }
    private func startRecording() async {
        noSpeechDetected = false
        deliveryConfirmed = false
        do {
            guard await AudioRecorder.requestPermission() else {
                throw DictationError.message("Microphone permission is required. Enable Brief under System Settings → Privacy & Security → Microphone.")
            }
            guard !releasedDuringPreparation else {
                phase = .idle; message = "Ready · hold the shortcut while speaking"; return
            }
            let rate = try recorder.prepare()
            var session = DictationSession(sampleRate: rate,
                profileName: "All projects", vocabulary: settings.vocabularyContext,
                targetApplication: target?.application)
            session.language = settings.language
            try Vocabulary.validate(session.vocabulary)
            try await store.create(session) // Persist recovery metadata before touching the microphone.
            if releasedDuringPreparation {
                try await store.update(session.id) { $0.state = .failed; $0.note = "Shortcut released before the microphone was ready." }
                phase = .idle; message = "Ready · hold the shortcut while speaking"
                await refreshHistory(); return
            }
            activeSessionID = session.id
            try recorder.start(at: store.audioURL(for: session.id))
            phase = .recording; elapsed = 0
            levels = Array(repeating: 0.03, count: 28)
            message = "Recording · \(session.profileName)"
            errorMessage = nil
            beginActivity()
            startTicker()
            showOverlay?()
            await refreshHistory()
        } catch {
            _ = await recorder.stop()
            if let id = activeSessionID {
                let description = error.localizedDescription
                do { try await store.update(id) { $0.state = .failed; $0.note = description } }
                catch { errorMessage = "Could not update recovery metadata: \(error.localizedDescription)" }
            }
            phase = .idle; activeSessionID = nil; stopTicker(); endActivity()
            report(error); await refreshHistory()
        }
    }
    private func finishRecording(transcribe: Bool, failure: String? = nil) async {
        guard let id = activeSessionID else { phase = .idle; return }
        let result = await recorder.stop()
        let failure = failure ?? result.error
        do {
            let session = try await store.update(id) {
                $0.frameCount = result.frames
                $0.state = failure == nil && result.frames > 0 ? .captured : .failed
                $0.note = failure ?? (result.frames == 0 ? "No audio samples were captured." : nil)
            }
            await refreshHistory()
            if transcribe && failure == nil && result.frames > 0 {
                phase = .transcribing
                await transcribeSession(session, automaticInsertion: true)
            } else {
                phase = .idle; activeSessionID = nil; stopTicker(); endActivity()
                message = failure ?? "Audio saved to History."
                showOverlayTemporarily()
            }
        } catch {
            // Do not start recognition if its source recording metadata cannot be committed.
            phase = .idle; activeSessionID = nil; stopTicker(); endActivity()
            report(error)
        }
    }
    func stopAndKeepAudio() {
        guard phase == .recording else { return }
        phase = .stopping
        operationTask = Task { await finishRecording(transcribe: false) }
    }
    func retry(_ session: DictationSession, useCurrentVocabulary: Bool) {
        guard !isBusy else { return }
        phase = .transcribing
        activeSessionID = session.id
        focusChanged = true; target = nil
        beginActivity()
        operationTask = Task {
            do {
                var saved = session
                if useCurrentVocabulary {
                    let context = settings.vocabularyContext
                    let profile = "All projects"
                    let language = settings.language
                    saved = try await store.update(session.id) {
                        $0.vocabulary = context; $0.profileName = profile; $0.language = language
                    }
                }
                await transcribeSession(saved, automaticInsertion: false)
            } catch { phase = .idle; activeSessionID = nil; endActivity(); report(error) }
        }
    }
    private func transcribeSession(_ session: DictationSession, automaticInsertion: Bool) async {
        noSpeechDetected = false
        deliveryConfirmed = false
        defer { phase = .idle; activeSessionID = nil; stopTicker(); endActivity(); Task { await refreshHistory() } }
        do {
            guard modelAvailable else {
                throw DictationError.message("Audio saved. Download or choose a local model in Settings, then retry from History.")
            }
            try await store.update(session.id) { $0.state = .transcribing; $0.note = nil }
            message = "Transcribing locally…"
            showOverlay?(); await refreshHistory()
            let response = try await worker.request(WorkerRequest(operation: .transcribe,
                modelDirectory: settings.modelDirectory, audioPath: store.audioURL(for: session.id).path,
                sampleRate: session.sampleRate, context: session.vocabulary, language: session.language,
                tokenBudgetMultiplier: settings.tokenBudgetMultiplier))
            modelLoaded = true
            guard let attempt = response.attempt else { throw DictationError.message("The recogniser returned no transcription result.") }
            // Commit the transcript before any delivery attempt. Failure to save prevents insertion.
            try await store.appendAttempt(attempt, to: session.id)
            await refreshHistory()
            selectedSessionID = session.id
            if attempt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                noSpeechDetected = true
                message = "No speech detected · nothing inserted"
                showOverlayTemporarily()
                return
            }
            if settings.effectiveTidyWording && attempt.warnings.isEmpty {
                message = "Tidying wording locally…"
                let cleanup = try await tidy(attempt.text, context: session.vocabulary, audioSeconds: session.duration)
                try Task.checkCancellation()
                try await store.update(session.id) { $0.cleanup = cleanup }
                await refreshHistory()
            }
            try Task.checkCancellation()
            let deliveryText = sessions.first(where: { $0.id == session.id })?.text ?? attempt.text
            message = attempt.warnings.isEmpty ? "Transcription saved · ready to insert" : "Saved · review needed in History"
            var copied = false
            if settings.shouldCopyTranscript(deliveryText, newRecording: automaticInsertion) {
                NSPasteboard.general.clearContents()
                copied = NSPasteboard.general.setString(deliveryText, forType: .string)
                await saveDeliveryNote(copied ? "Copied to clipboard · press ⌘V to paste"
                    : "Could not copy automatically. Use Copy text.", for: session.id)
            }
            if automaticInsertion && settings.automaticInsertion,
               let saved = sessions.first(where: { $0.id == session.id }) {
                await deliver(saved, automatic: true, alreadyCopied: copied)
            }
            showOverlayTemporarily()
        } catch {
            let description = error is CancellationError ? "Processing stopped. Audio was retained for retry." : error.localizedDescription
            do {
                try await store.update(session.id) {
                    $0.state = $0.attempts.isEmpty ? .failed : .needsReview
                    $0.note = description
                }
            } catch { errorMessage = "Could not update the recording entry: \(error.localizedDescription)" }
            message = description
            await refreshHistory(); showOverlayTemporarily()
        }
    }
    private func tidy(_ original: String, context: String, audioSeconds: Double) async throws -> TranscriptCleanup {
        func fallback(_ note: String) -> TranscriptCleanup {
            TranscriptCleanup(original: original, text: original, model: CleanupPolicy.repository, note: note)
        }
        try Task.checkCancellation()
        guard CleanupPolicy.shouldAttempt(original) else {
            return fallback("No text to tidy.")
        }
        guard let path = settings.cleanupModelDirectory, !path.isEmpty else {
            return fallback("Cleanup model not installed. Original kept.")
        }
        let budget = CleanupPolicy.waitBudget(audioSeconds: audioSeconds)
        guard budget > 0 else { return fallback("Recording duration unavailable · original kept.") }
        tidyingWording = true
        cleanupSkipped = false
        let started = ContinuousClock.now
        let timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(budget)) } catch { return }
            self?.cleanupWorker.stop()
        }
        defer { timeout.cancel(); cleanupWorker.stop(); tidyingWording = false }
        do {
            let response = try await cleanupWorker.request(WorkerRequest(operation: .cleanup,
                modelDirectory: path, text: original, context: context))
            try Task.checkCancellation()
            guard ContinuousClock.now - started < .seconds(budget), !cleanupSkipped else {
                return fallback("Cleanup skipped or time limit reached · original used.")
            }
            guard let result = response.cleanup, result.original == original else {
                return fallback("Cleanup returned an invalid result. Original kept.")
            }
            return result
        } catch {
            try Task.checkCancellation()
            return fallback(cleanupSkipped ? "Cleanup skipped · original used." : "Cleanup exceeded its time limit or was unavailable · original used.")
        }
    }
    func skipCleanup() {
        guard tidyingWording else { return }
        cleanupSkipped = true
        cleanupWorker.stop()
    }
    func copyOriginal(_ session: DictationSession) {
        guard let original = session.cleanup?.original else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(original, forType: .string) {
            message = "Original copied"
        }
    }
    func downloadCleanupModel() {
        guard !isBusy else { return }
        phase = .downloading; errorMessage = nil
        operationTask = Task {
            defer { phase = .idle }
            do {
                let destination = try await installer.install(under: root.appendingPathComponent("Models"),
                    repository: CleanupPolicy.repository) { [weak self] status in
                    Task { @MainActor [weak self] in self?.downloadMessage = status }
                }
                var updated = settings; updated.cleanupModelDirectory = destination.path
                // Downloading is an explicit opt-in to trying wording cleanup.
                updated.tidyWording = true
                phase = .idle
                try apply(updated)
                downloadMessage = "Cleanup ready · Tidy wording is on."
            } catch {
                if error is CancellationError { downloadMessage = "Download cancelled." }
                else { report(error) }
            }
        }
    }
    func insertPending() {
        guard !isBusy else { return }
        guard let session = pendingSession else { message = "No pending transcription. Open History to select one."; showOverlayTemporarily(); return }
        // Reserve the phase across the asynchronous persistence write to prevent duplicate hotkeys.
        phase = .stopping
        operationTask = Task {
            await deliver(session, automatic: false)
            phase = .idle; showOverlayTemporarily()
        }
    }
    private func deliver(_ session: DictationSession, automatic: Bool, alreadyCopied: Bool = false) async {
        deliveryConfirmed = false
        let recovery = alreadyCopied ? "Text is on the clipboard · press ⌘V to paste." : "Use Copy text."
        guard session.canInsert else { return }
        let current = insertion.capture()
        let decision = DeliveryPolicy.decide(DeliveryConditions(automatic: automatic,
            automaticEnabled: settings.automaticInsertion, trusted: InsertionService.trusted,
            sameTarget: target?.matches(current) == true, focusChangedDuringRecording: focusChanged,
            editable: current?.editable ?? false, secure: current?.secure ?? false,
            terminal: insertion.isTerminal(current), allowTerminal: settings.allowTerminalApps,
            requiresReview: session.state == .needsReview))
        guard case .insert = decision, let current else {
            if case .hold(let reason) = decision {
                let detail = current.map { $0.editable ? "" : " Field type: \($0.role.isEmpty ? "unknown" : $0.role)." } ?? " No focused field was identified."
                await saveDeliveryNote("Not inserted. \(reason)\(detail) \(recovery)", for: session.id)
            }
            return
        }
        do {
            let method = try insertion.method(for: current, allowPaste: settings.allowPasteFallback)
            // Persist intent before the side effect. A crash here must not cause an automatic retry.
            try await store.update(session.id) { $0.delivery = .insertionRequested }
            guard current.matches(insertion.capture()) else {
                try await store.update(session.id) { $0.delivery = .pending }
                await saveDeliveryNote("Not inserted: the focused field changed before delivery. \(recovery)", for: session.id)
                return
            }
            let expected = insertion.expectedValue(for: current, text: session.text)
            try insertion.insert(session.text, into: current, method: method)
            let delivery: DeliveryState = method == .accessibility ? .inserted : .pasteRequested
            try await store.update(session.id) { $0.delivery = delivery }
            stagedSessionID = nil
            deliveryConfirmed = await insertion.verifyInsertion(into: current, expected: expected)
            if deliveryConfirmed {
                try await store.update(session.id) { $0.delivery = .confirmed }
                await saveDeliveryNote("Inserted into \(current.application)", for: session.id)
                return
            }
            await saveDeliveryNote(method == .accessibility
                ? "Text sent through Accessibility to \(current.application). Check the field."
                : "Paste sent to \(current.application). Text is on the clipboard if you need to paste again with ⌘V.", for: session.id)
        } catch { await saveDeliveryNote("Insertion not confirmed: \(error.localizedDescription) \(recovery)", for: session.id) }
        await refreshHistory()
    }
    private func saveDeliveryNote(_ note: String, for id: UUID) async {
        message = note
        do { try await store.update(id) { $0.deliveryNote = note } }
        catch { errorMessage = "Could not save delivery status: \(error.localizedDescription)" }
        await refreshHistory()
    }
    func stage(_ id: UUID) {
        Task {
            do {
                try await store.update(id) { $0.delivery = .pending }
                stagedSessionID = id
                await refreshHistory()
                message = "Select your destination field, then press \(settings.insertShortcut.display)."
                showOverlayTemporarily()
            } catch { report(error) }
        }
    }
    func saveEdit(_ id: UUID, text: String) async throws {
        guard !isBusy else { throw DictationError.message("Finish the current operation before editing history.") }
        try await store.update(id) { $0.editedText = text; $0.delivery = .pending }
        await refreshHistory()
    }
    func setRecoveryPolicy(_ policy: RecoveryPolicy) {
        do { var updated = settings; updated.recoveryPolicy = policy; try apply(updated) }
        catch { report(error) }
    }
    func showLatestTranscript() { noSpeechDetected = false; deliveryConfirmed = false; showOverlayTemporarily() }
    func copy(_ session: DictationSession) {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(session.text, forType: .string) else { report(DictationError.message("Could not copy the transcript.")); return }
        message = "Copied to clipboard"
        Task {
            do { try await store.update(session.id) { $0.delivery = .copied }; await refreshHistory() }
            catch { report(error) }
        }
    }
    func archive(_ id: UUID) {
        Task {
            do { try await store.update(id) { $0.delivery = .dismissed }; await refreshHistory() }
            catch { report(error) }
        }
    }
    func delete(_ session: DictationSession, audioOnly: Bool) {
        guard !isBusy else { return }
        Task {
            do {
                stopPlayback()
                if audioOnly { try await store.deleteAudio(session.id) }
                else { try await store.delete(session.id); if selectedSessionID == session.id { selectedSessionID = nil } }
                await refreshHistory()
            } catch { report(error) }
        }
    }
    func play(_ session: DictationSession) {
        do {
            stopPlayback()
            let preview = root.appendingPathComponent("preview.wav")
            try PCMFile.exportWAV(from: store.audioURL(for: session.id), sampleRate: session.sampleRate, to: preview)
            player = try AVAudioPlayer(contentsOf: preview)
            player?.play()
        } catch { report(error) }
    }
    func stopPlayback() { player?.stop(); player = nil; try? FileManager.default.removeItem(at: root.appendingPathComponent("preview.wav")) }
    func exportAudio(_ session: DictationSession) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Dictation-\(session.id.uuidString.prefix(8)).wav"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try PCMFile.exportWAV(from: store.audioURL(for: session.id), sampleRate: session.sampleRate, to: url) }
        catch { report(error) }
    }
    func reveal(_ session: DictationSession) {
        NSWorkspace.shared.activateFileViewerSelecting([store.directory(for: session.id)])
    }
    func scanRepositories(path: String) {
        guard !scanningRepositories else { return }
        scanningRepositories = true
        repositoryScanMessage = "Finding project names…"
        repositoryScanTask = Task {
            defer { scanningRepositories = false }
            do {
                let result = try await Task.detached(priority: .utility) {
                    try RepositoryScanner.scan(path: path)
                }.value
                // Merge into the latest saved settings, without changing an in-flight recording's snapshot.
                var updated = settings
                updated.repositoriesPath = path
                updated.repositoryVocabulary = result
                try updated.validate()
                try SettingsFile.save(updated, to: settingsURL)
                settings = updated
                repositoryScanMessage = "\(result.names.count) project names saved"
            } catch {
                repositoryScanMessage = "Scan failed: \(error.localizedDescription) Previous vocabulary is still available."
            }
        }
    }

    func warmModel() {
        guard !isBusy else { return }
        phase = .loading; message = "Loading the local model…"
        operationTask = Task {
            defer { phase = .idle }
            do {
                _ = try await worker.request(WorkerRequest(operation: .load, modelDirectory: settings.modelDirectory))
                modelLoaded = true; message = "Model loaded · ready to record"
            } catch { report(error) }
        }
    }
    func unloadModel() { guard !isBusy else { return }; worker.stop(); modelLoaded = false; message = "Model unloaded; audio and history are unchanged." }
    func downloadModel() {
        guard !isBusy else { return }
        phase = .downloading; errorMessage = nil
        operationTask = Task {
            do {
                let destination = try await installer.install(under: root.appendingPathComponent("Models")) { [weak self] status in
                    Task { @MainActor [weak self] in self?.downloadMessage = status }
                }
                phase = .idle
                var updated = settings; updated.modelDirectory = destination.path
                try apply(updated)
                warmModel()
            } catch {
                phase = .idle
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { downloadMessage = "Download cancelled." }
                else { report(error) }
            }
        }
    }
    func cancelProcessing() {
        guard [.transcribing, .loading, .downloading].contains(phase) else { return }
        operationTask?.cancel()
        worker.stop(); cleanupWorker.stop()
    }
    func shutdown() async {
        overlayDismissTask?.cancel()
        if phase == .stopping || phase == .preparing { await operationTask?.value }
        if phase == .recording { phase = .stopping; await finishRecording(transcribe: false) }
        operationTask?.cancel(); worker.stop(); cleanupWorker.stop()
        await operationTask?.value
        recoveryTimer?.invalidate(); recoveryTimer = nil
        hotKeys.unregister(); stopTicker(); endActivity(); stopPlayback()
    }
    func report(_ error: Error) {
        let description = error is CancellationError ? "Operation cancelled. Saved recordings are unchanged." : error.localizedDescription
        errorMessage = description; message = description
        showOverlayTemporarily()
    }
    private func beginActivity() {
        if activity == nil { activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Recording or transcribing dictation") }
    }
    private func endActivity() { if let activity { ProcessInfo.processInfo.endActivity(activity) }; activity = nil }
    private func startTicker() {
        stopTicker(); tickCount = 0
        ticker = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }
    private func tick() {
        if phase == .recording {
            let value = recorder.snapshot
            elapsed = Double(value.frames) / recorder.sampleRate
            levels.removeFirst(); levels.append(max(0.025, value.level))
            if let error = value.error {
                phase = .stopping
                operationTask = Task { await finishRecording(transcribe: false, failure: error) }
                return
            }
            if Date().timeIntervalSince(value.lastBufferAt) > 5 {
                phase = .stopping
                operationTask = Task { await finishRecording(transcribe: false, failure: "Microphone audio stopped arriving. Saved audio was retained.") }
                return
            }
        }
        tickCount += 1
        if tickCount % 5 == 0 && !focusChanged && [.recording, .stopping, .transcribing].contains(phase) {
            focusChanged = target?.matches(insertion.capture()) != true
        }
    }
    private func showOverlayTemporarily() {
        overlayDismissTask?.cancel(); showOverlay?()
        overlayDismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(self?.deliveryConfirmed == true && self?.latestTranscript?.cleanup?.changed != true ? 1 : 5)) } catch { return }
            guard let self, self.phase == .idle else { return }
            if let fade = self.fadeOverlay { fade() } else { self.hideOverlay?() }
        }
    }
}
