import AppKit
import DictationCore

/// Synthetic integration check using the actual app-to-worker transport, with ASR
/// left loaded as it is during everyday dictation. Never records or reads messages.
@MainActor enum CleanupDiagnostics {
    static func run() async -> Int32 {
        let speech = WorkerClient(), editor = WorkerClient()
        defer { speech.stop(); editor.stop() }
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let settings = try SettingsFile.load(from: root.appendingPathComponent("LocalDictation/settings.json"))
            guard let model = settings.cleanupModelDirectory else { throw DictationError.message("Install the cleanup model first.") }
            _ = try await speech.request(WorkerRequest(operation: .load, modelDirectory: settings.modelDirectory))
            let text = "I think it would be really good to add a copy button to Blint. The the text should remain available if the field loses focus. Do not change the project names or remove any conditions. "
            for count in [1, 4, 1] {
                let started = ContinuousClock.now
                let timeout = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    editor.stop()
                }
                defer { timeout.cancel() }
                let response = try await editor.request(WorkerRequest(operation: .cleanup,
                    modelDirectory: model, text: String(repeating: text, count: count), context: "Blint"))
                timeout.cancel()
                guard response.cleanup != nil else { throw DictationError.message("Missing cleanup result.") }
                editor.stop() // Exercise the fresh helper used for each dictation.
                print("Cleanup with recogniser loaded: \(text.count * count) characters, \(ContinuousClock.now - started)")
            }
            // A skipped edit must unblock immediately and allow the next request.
            let pending = Task { try await editor.request(WorkerRequest(operation: .cleanup,
                modelDirectory: model, text: text, context: "Blint")) }
            try await Task.sleep(for: .milliseconds(50))
            editor.stop()
            do {
                _ = try await pending.value
                throw DictationError.message("Stopped request unexpectedly succeeded.")
            } catch is CancellationError { }
            let resumed = try await editor.request(WorkerRequest(operation: .cleanup,
                modelDirectory: model, text: "The the quality of the sentence is good.", context: "Blint"))
            guard resumed.cleanup?.text == "The quality of the sentence is good." else { throw DictationError.message("Restart lost cleanup result.") }
            _ = try await speech.request(WorkerRequest(operation: .load, modelDirectory: settings.modelDirectory))
            print("Skip, helper restart, and subsequent recogniser request passed.")
            return 0
        } catch {
            fputs("Cleanup transport check failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}
