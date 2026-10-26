import AppKit
import DictationCore

/// Synthetic integration check using the actual app-to-worker transport, with ASR
/// left loaded as it is during everyday dictation. Never records or reads messages.
@MainActor enum CleanupDiagnostics {
    /// Exercises the real controller delivery path using a private pasteboard and
    /// temporary history. Never touches the user's clipboard or focused field.
    static func checkEarlyCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Brief-early-copy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = AppSettings()
        settings.automaticInsertion = false
        settings.automaticClipboardCopy = true
        try SettingsFile.save(settings, to: root.appendingPathComponent("settings.json"))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let controller = try AppController(storageRoot: root, transcriptPasteboard: pasteboard)
        for (takeOriginal, changeClipboard) in [(true, false), (true, true), (false, false)] {
            let session = DictationSession(sampleRate: 16000, profileName: "Test", vocabulary: "")
            let attempt = TranscriptAttempt(text: "The the quality is good.", model: "test", vocabulary: "", processingSeconds: 0, audioSeconds: 60, generationTokens: 0)
            try await controller.store.create(session)
            try await controller.store.appendAttempt(attempt, to: session.id)
            await controller.refreshHistory()
            guard let saved = controller.sessions.first(where: { $0.id == session.id }) else { throw DictationError.message("Missing test session.") }
            pasteboard.clearContents()
            pasteboard.setString("Unrelated earlier clipboard content", forType: .string)
            controller.beginCleanupPresentation(saved, automaticallyCopy: true)
            guard pasteboard.string(forType: .string) == attempt.text else {
                throw DictationError.message("Original was not automatically copied before cleanup.")
            }
            if takeOriginal {
                controller.copyCleanupOriginal()
                guard pasteboard.string(forType: .string) == attempt.text else { throw DictationError.message("Original was not available while tidying.") }
            }
            if changeClipboard {
                pasteboard.clearContents()
                pasteboard.setString("A newer clipboard choice", forType: .string)
            }
            try await controller.store.update(session.id) {
                $0.cleanup = TranscriptCleanup(original: attempt.text, text: "The quality is good.", model: "test")
            }
            await controller.refreshHistory()
            try await controller.finishTranscriptDelivery(saved, attempt: attempt, automaticInsertion: true)
            let expected = changeClipboard ? "A newer clipboard choice" : (takeOriginal ? attempt.text : "The quality is good.")
            guard pasteboard.string(forType: .string) == expected,
                  controller.cleanupPreview == nil,
                  controller.sessions.first(where: { $0.id == session.id })?.text == "The quality is good." else {
                throw DictationError.message("Cleanup replaced an early clipboard choice or lost the edited result.")
            }
            controller.copyCleanupOriginal() // A stale button action must do nothing.
            guard pasteboard.string(forType: .string) == expected else { throw DictationError.message("Stale preview copied old text.") }
        }
        var disabled = settings
        disabled.automaticClipboardCopy = false
        let disabledRoot = root.appendingPathComponent("disabled-copy")
        try FileManager.default.createDirectory(at: disabledRoot, withIntermediateDirectories: true)
        try SettingsFile.save(disabled, to: disabledRoot.appendingPathComponent("settings.json"))
        let disabledController = try AppController(storageRoot: disabledRoot, transcriptPasteboard: pasteboard)
        if let saved = controller.latestTranscript {
            pasteboard.clearContents()
            pasteboard.setString("Keep clipboard", forType: .string)
            disabledController.beginCleanupPresentation(saved, automaticallyCopy: true)
            guard pasteboard.string(forType: .string) == "Keep clipboard" else {
                throw DictationError.message("Early copy ignored the clipboard setting.")
            }
            controller.beginCleanupPresentation(saved, automaticallyCopy: false)
            guard pasteboard.string(forType: .string) == "Keep clipboard" else {
                throw DictationError.message("A retry or preview changed the clipboard.")
            }
        }
        print("Automatic original copy, disabled copy preference, early original copy, newer clipboard preservation, completed edit, and next-clip automatic copy passed.")
    }
    static func run() async -> Int32 {
        let speech = WorkerClient(), editor = WorkerClient()
        defer { speech.stop(); editor.stop() }
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let settings = try SettingsFile.load(from: root.appendingPathComponent("LocalDictation/settings.json"))
            guard let model = settings.cleanupModelDirectory else { throw DictationError.message("Install the cleanup model first.") }
            _ = try await speech.request(WorkerRequest(operation: .load, modelDirectory: settings.modelDirectory))
            let text = "I think it would be really good to add a copy button to Blint. The the text should remain available if the field loses focus. Do not change the project names or remove any conditions. "
            let paragraphs = [
                "The the settings page for Blint should explain which project is selected. Keep the project name visible while someone edits a specification, so they can check that their notes belong to the correct workspace. Do not change the existing keyboard shortcuts.",
                "When a document has unsaved changes, show a small indicator beside its title. Saving should update that indicator only after the file has been written successfully. If the disk is unavailable, keep the draft in memory and explain what happened without closing the editor.",
                "The project list needs a search field that matches names without requiring exact capitalization. Keep recently opened projects near the top, but make it possible to browse the full list alphabetically. Searching must not rename projects or modify their folders.",
                "For the export flow, let people choose Markdown or plain text. Include the complete specification and preserve code blocks in the Markdown version. Show the destination before writing the file. If a file already exists, ask before replacing its contents.",
                "I think the activity panel could show a short summary of the latest task. It might be useful to display whether the agent is working or waiting for an answer. Avoid showing a permanent log of every intermediate action, because the screen should remain easy to scan.",
                "The documentation should describe how to create a project, attach a specification, and review the result. Use a small example with realistic project names. Explain what happens when the connection is lost, and make sure the recovery instructions match the actual interface.",
                "Please keep the current JSON configuration format compatible with older versions. New optional fields should have sensible defaults when they are missing. Do not remove unknown fields when saving a document, because another tool might still need that information.",
                "For accessibility, every icon button needs a descriptive label. The main editor should remain usable with the keyboard, and focus should move predictably when a dialog closes. Check the layout with larger text and with long project names rather than assuming everything fits.",
                "A failed operation should leave the original document available. The retry action should repeat only the failed step, not create another project or send the same message twice. Keep the error explanation brief and provide enough detail for someone to decide what to do next.",
                "Before releasing this change, check the normal save flow, a missing folder, and a read-only destination. The existing project names and file paths must remain unchanged. If any of those cases are uncertain, leave the behavior as it is and describe the remaining question."
            ]
            let longSpecification = ["Atlas", "Beacon", "Cobalt", "Delta"].map {
                "For project \($0):\n\n" + paragraphs.joined(separator: "\n\n")
            }.joined(separator: "\n\n")
            for (sample, audioSeconds) in [(text, 30.0), (paragraphs.prefix(5).joined(separator: "\n\n"), 120.0), (paragraphs.joined(separator: "\n\n"), 300.0), (longSpecification, 600.0)] {
                let budget = CleanupPolicy.waitBudget(audioSeconds: audioSeconds)
                let started = ContinuousClock.now
                let timeout = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(budget)) } catch { return }
                    editor.stop()
                }
                defer { timeout.cancel() }
                let response = try await editor.request(WorkerRequest(operation: .cleanup,
                    modelDirectory: model, text: sample, context: "Blint"))
                timeout.cancel()
                guard let cleanup = response.cleanup else { throw DictationError.message("Missing cleanup result.") }
                editor.stop() // Exercise the fresh helper used for each dictation.
                print("Cleanup with recogniser loaded: \(sample.count) characters, budget \(budget)s, \(ContinuousClock.now - started), changed: \(cleanup.changed), note: \(cleanup.note ?? "none")")
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
