import AppKit
import DictationCore
import SwiftUI

/// Deterministic lifecycle checks: real controller and disk store, isolated clipboard,
/// scripted workers and microphone. Does not capture audio, inspect focus or paste.
@MainActor enum RecordingDiagnostics {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Brief-recordings-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = AppSettings()
        settings.modelDirectory = root.path
        settings.cleanupModelDirectory = root.path
        settings.tidyWording = true
        settings.automaticInsertion = true
        try SettingsFile.save(settings, to: root.appendingPathComponent("settings.json"))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let speech = ScriptedWorker(), cleanup = ScriptedWorker()
        let controller = try AppController(storageRoot: root, transcriptPasteboard: pasteboard,
            recorder: ScriptedRecorder(), worker: speech, cleanupWorker: cleanup,
            requestMicrophonePermission: { true }, captureFocus: { nil })
        do {
            func start() async throws -> UUID {
                try require(controller.canStartRecording, "Capture was blocked by processing")
                controller.toggleRecording()
                try await until("microphone start") { controller.phase == .recording }
                return controller.batch.items.last!.id
            }
            func stop() async throws {
                controller.toggleRecording()
                try await until("audio finalization") { controller.canStartRecording }
            }
            let a = try await start()
            let group = controller.batch.id
            try await stop()
            try await until("first recognition") { speech.pending != nil }
            controller.hotKeys.onAction?(1, true)
            try await until("held shortcut during recognition") { controller.phase == .recording }
            let b = controller.batch.items.last!.id
            speech.transcript("First first recording.")
            try await until("first cleanup") { cleanup.pending != nil }
            try require(controller.phase == .recording, "ASR completion stopped the newer capture")
            try require(controller.batch.items.first?.stage == .cleaning, "First cell lost cleanup status")
            try require(pasteboard.string(forType: .string) == "First first recording.", "Original unavailable during cleanup")
            controller.hotKeys.onAction?(1, false)
            try await until("shortcut release during cleanup") { controller.canStartRecording }
            try require(controller.batch.items.last?.stage == .queued, "Second recording was not queued")
            let c = try await start()
            if CommandLine.arguments.contains("--snapshot-multiple-recordings") {
                try await snapshot(controller)
            }
            cleanup.cleaned("First recording.")
            try await until("second recognition") { speech.pending != nil }
            try require(controller.phase == .recording, "Cleanup completion stopped the newer capture")
            try require(controller.batch.items.first?.stage == .complete, "First cell did not complete independently")
            try await stop()
            speech.transcript("Second second recording.")
            try await until("second cleanup") { cleanup.pending != nil }
            controller.copyCleanupOriginal(b)
            cleanup.cleaned("Second recording.")
            try await until("third recognition") { speech.pending != nil }
            try require(pasteboard.string(forType: .string) == "First recording.\n\nSecond second recording.", "Original selection replaced earlier group text")
            speech.transcript("Third third recording.")
            try await until("third cleanup") { cleanup.pending != nil }
            try require(pasteboard.string(forType: .string) == "First recording.\n\nSecond second recording.\n\nThird third recording.", "Available originals were not appended")
            cleanup.cleaned("Third recording.")
            try await until("group completion") { !controller.isBusy }
            let groupedText = "First recording.\n\nSecond second recording.\n\nThird recording."
            try require(controller.batch.id == group && controller.batch.items.map(\.id) == [a, b, c], "Overlap chain lost its group or order")
            try require(pasteboard.string(forType: .string) == groupedText, "Final group clipboard was incorrect")
            await controller.refreshHistory()
            try require(Set(controller.sessions.map(\.id)) == [a, b, c], "Latest-only retention pruned part of a group")
            try require(controller.sessions.allSatisfy { $0.clipboardGroupID == group }, "Group identity was not persisted")
            try require(controller.sessions.allSatisfy { [.pending, .copied].contains($0.delivery) }, "Growing group requested insertion")

            let d = try await start()
            try require(controller.batch.id != group && controller.batch.items.count == 1, "Independent recording did not start a fresh group")
            try require(pasteboard.string(forType: .string) == groupedText, "Starting a recording prematurely cleared the clipboard")
            try await stop()
            try await until("independent recognition") { speech.pending != nil }
            speech.transcript("Independent recording.")
            try await until("independent cleanup") { cleanup.pending != nil }
            cleanup.fail()
            try await until("cleanup fallback") { !controller.isBusy }
            try require(pasteboard.string(forType: .string) == "Independent recording.", "Fresh group did not replace the previous clipboard")
            await controller.refreshHistory()
            try require(controller.sessions.map(\.id) == [d], "Finished old group did not expire")

            let e = try await start(); try await stop()
            try await until("cancellable recognition") { speech.pending != nil }
            let f = try await start(); try await stop()
            let g = try await start()
            controller.cancelProcessing(f)
            controller.cancelProcessing(e)
            try await until("independent cancellations") {
                controller.batch.items.filter { $0.id == e || $0.id == f }.allSatisfy { !$0.stage.isActive }
            }
            try require(controller.phase == .recording && controller.batch.items.last?.id == g, "Cancelling earlier cells stopped capture")
            controller.stopAndKeepAudio()
            try await until("audio-only completion") { !controller.isBusy }
            try require(pasteboard.string(forType: .string) == "Independent recording.", "Cancelled/audio-only group replaced clipboard")
            for id in [e, f, g] {
                let saved = try await controller.store.read(id)
                try require(saved.frameCount > 0, "Cancellation lost recorded audio")
            }

            let h = try await start(); try await stop()
            try await until("failed recognition") { speech.pending != nil }
            let i = try await start(); try await stop()
            speech.fail()
            try await until("recognition after failure") { speech.pending != nil && controller.processingSessionID == i }
            speech.transcript(" ")
            try await until("empty result completion") { !controller.isBusy }
            try require(controller.batch.items.first?.id == h && controller.batch.items.first?.stage == .failed, "Failure lost its own cell")
            try require(pasteboard.string(forType: .string) == "Independent recording.", "Empty result replaced usable text")

            let skipped = try await start(); try await stop()
            try await until("recognition before skip") { speech.pending != nil }
            speech.transcript("Keep the original.")
            try await until("cleanup before skip") { cleanup.pending != nil }
            _ = try await start()
            controller.skipCleanup(skipped)
            try await until("skip cleanup independently") { controller.batch.items.first?.stage == .complete }
            try require(controller.phase == .recording, "Skipping cleanup interrupted a newer capture")
            try require(pasteboard.string(forType: .string) == "Keep the original.", "Skipping cleanup lost original text")
            controller.stopAndKeepAudio()
            try await until("capture after cleanup skip") { !controller.isBusy }

            let j = try await start(); try await stop()
            try await until("shutdown recognition") { speech.pending != nil }
            let k = try await start(); try await stop()
            let l = try await start()
            await controller.shutdown()
            for id in [j, k, l] {
                let saved = try await controller.store.read(id)
                try require(saved.frameCount > 0 && ![.recording, .transcribing].contains(saved.state), "Shutdown did not retain and settle each recording")
            }
            print("Multiple recording lifecycle passed: capture during ASR/cleanup, queue order, independent cells, grouped clipboard, original selection, fresh groups, retention, cancellation, failure, empty speech, and shutdown.")
        } catch {
            await controller.shutdown()
            throw error
        }
    }
    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw DictationError.message(message) }
    }
    private static func snapshot(_ controller: AppController) async throws {
        let window = NSWindow(contentRect: NSRect(x: -2000, y: 0, width: 446, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let view = NSHostingView(rootView: RecordingOverlay(controller: controller) { height in
            window.setContentSize(NSSize(width: 446, height: height))
        })
        window.contentView = view
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw DictationError.message("Could not render recording stack")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw DictationError.message("Could not encode recording stack")
        }
        try png.write(to: URL(fileURLWithPath: "/tmp/brief-recording-stack.png"))
        print("Rendered /tmp/brief-recording-stack.png")
    }
    private static func until(_ label: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw DictationError.message("Timed out: " + label) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor private final class ScriptedRecorder: RecordingAudio {
    let sampleRate: Double = 16000
    var snapshot: RecordingMeter { RecordingMeter(frames: 16000 * 600, level: 0.4) }
    func prepare() throws -> Double { sampleRate }
    func start(at url: URL) throws { try Data(repeating: 0, count: 16).write(to: url) }
    func stop() async -> RecordingMeter { snapshot }
}

@MainActor private final class ScriptedWorker: DictationWorking {
    var onExit: (() -> Void)?
    var pending: (WorkerRequest, CheckedContinuation<WorkerResponse, Error>)?
    func request(_ request: WorkerRequest) async throws -> WorkerResponse {
        guard pending == nil else { throw DictationError.message("Concurrent worker requests") }
        return try await withCheckedThrowingContinuation { pending = (request, $0) }
    }
    func transcript(_ text: String) {
        guard let (request, continuation) = pending else { return }
        pending = nil
        continuation.resume(returning: WorkerResponse(id: request.id, success: true,
            attempt: TranscriptAttempt(text: text, model: "test", vocabulary: "", processingSeconds: 0, audioSeconds: 600, generationTokens: 0)))
    }
    func cleaned(_ text: String) {
        guard let (request, continuation) = pending else { return }
        pending = nil
        continuation.resume(returning: WorkerResponse(id: request.id, success: true,
            cleanup: TranscriptCleanup(original: request.text ?? "", text: text, model: "test")))
    }
    func fail() {
        let continuation = pending?.1; pending = nil
        continuation?.resume(throwing: DictationError.message("Scripted worker failure"))
    }
    func stop() {
        let continuation = pending?.1; pending = nil
        continuation?.resume(throwing: CancellationError())
        onExit?()
    }
}
