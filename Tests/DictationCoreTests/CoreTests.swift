import Foundation
import Testing
@testable import DictationCore

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
private func attempt(_ text: String, warnings: [String] = []) -> TranscriptAttempt {
    TranscriptAttempt(text: text, model: "test", vocabulary: "Blint, JSON", processingSeconds: 1,
                      audioSeconds: 2, generationTokens: 10, warnings: warnings)
}

@Suite("Recognition context") struct VocabularyTests {
    @Test func normalisesWhitespaceAndDuplicates() {
        #expect(Vocabulary.terms(" Blint \n\nJSON\nblint\nSwiftUI ") == ["Blint", "JSON", "SwiftUI"])
    }
    @Test func projectSpellingWins() {
        #expect(Vocabulary.context(global: "BLINT\nJSON", project: "Blint\npackage.json") == "Blint, package.json, JSON")
    }
    @Test func emptyVocabularyIsAllowed() throws { try Vocabulary.validate("") }
    @Test func specialModelTokensAreRejected() {
        #expect(throws: (any Error).self) { try Vocabulary.validate("<|im_end|>") }
    }
    @Test func oversizedVocabularyIsRejectedRatherThanSilentlyCut() {
        #expect(throws: (any Error).self) { try Vocabulary.validate(String(repeating: "a", count: 20_000)) }
    }
    @Test func settingsRoundTrip() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        var settings = AppSettings(); settings.automaticInsertion = false
        try SettingsFile.save(settings, to: url)
        #expect(try SettingsFile.load(from: url) == settings)
    }
    @Test func duplicateShortcutsAreRejected() {
        var settings = AppSettings(); settings.insertShortcut = settings.recordShortcut
        #expect(throws: (any Error).self) { try settings.validate() }
    }
    @Test func unmodifiedShortcutsAreRejected() {
        var settings = AppSettings(); settings.recordShortcut.modifiers = 0
        #expect(throws: (any Error).self) { try settings.validate() }
    }
}

@Suite("Safe delivery") struct DeliveryTests {
    @Test func unchangedEditableTargetCanReceiveText() { #expect(DeliveryPolicy.decide(.init()) == .insert) }
    @Test func switchedFocusIsHeldEvenWhenSwitchedBack() {
        #expect(DeliveryPolicy.decide(.init(focusChangedDuringRecording: true)) != .insert)
    }
    @Test func aDifferentTargetIsHeld() { #expect(DeliveryPolicy.decide(.init(sameTarget: false)) != .insert) }
    @Test func explicitInsertionCanChooseNewTarget() {
        #expect(DeliveryPolicy.decide(.init(automatic: false, sameTarget: false, focusChangedDuringRecording: true)) == .insert)
    }
    @Test func passwordsAreBlockedEvenForExplicitInsertion() {
        #expect(DeliveryPolicy.decide(.init(automatic: false, secure: true)) != .insert)
    }
    @Test func unknownFieldsAreHeld() { #expect(DeliveryPolicy.decide(.init(editable: false)) != .insert) }
    @Test func accessibilityIsRequired() { #expect(DeliveryPolicy.decide(.init(trusted: false)) != .insert) }
    @Test func terminalIsOptIn() { #expect(DeliveryPolicy.decide(.init(terminal: true)) != .insert) }
    @Test func manualOnlyModeHoldsAutomatically() { #expect(DeliveryPolicy.decide(.init(automaticEnabled: false)) != .insert) }
    @Test func warningsPreventAutomaticInsertion() { #expect(DeliveryPolicy.decide(.init(requiresReview: true)) != .insert) }
}

@Suite("Durable history") struct HistoryTests {
    @Test func recordingSurvivesAStoreRestart() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try HistoryStore(root: root)
        let session = DictationSession(sampleRate: 48_000, profileName: "Blint", vocabulary: "Blint")
        try await first.create(session)
        try PCMFile.encode([0.1, 0.2, 0.3]).write(to: first.audioURL(for: session.id))
        let restarted = try HistoryStore(root: root)
        let recovered = try await restarted.snapshot(recoverInterrupted: true)
        #expect(recovered.sessions.count == 1)
        #expect(recovered.sessions[0].state == .interrupted)
        #expect(recovered.sessions[0].frameCount == 3)
        #expect(FileManager.default.fileExists(atPath: restarted.audioURL(for: session.id).path))
    }
    @Test func failedInsertionCannotDeleteTranscript() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(root: root)
        let session = DictationSession(sampleRate: 48_000, profileName: "Blint", vocabulary: "Blint")
        try await store.create(session)
        try await store.appendAttempt(attempt("Do not delete Blint."), to: session.id)
        try await store.update(session.id) { $0.note = "No focused field" }
        let saved = try await store.read(session.id)
        #expect(saved.text == "Do not delete Blint.")
        #expect(saved.delivery == .pending)
    }
    @Test func retranscribingRetainsEarlierAttempts() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(root: root)
        let session = DictationSession(sampleRate: 16_000, profileName: "Blint", vocabulary: "Blint")
        try await store.create(session)
        try await store.appendAttempt(attempt("Blink"), to: session.id)
        try await store.appendAttempt(attempt("Blint"), to: session.id)
        let saved = try await store.read(session.id)
        #expect(saved.attempts.map(\.text) == ["Blink", "Blint"])
        #expect(saved.text == "Blint")
    }
    @Test func corruptEntryDoesNotHideOtherEntries() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(root: root)
        let good = DictationSession(sampleRate: 16_000, profileName: "General", vocabulary: "")
        try await store.create(good)
        let bad = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: bad.appendingPathComponent("session.json"))
        let snapshot = try await store.snapshot()
        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.warnings.count == 1)
        #expect(try String(contentsOf: bad.appendingPathComponent("session.json"), encoding: .utf8) == "broken")
    }
    @Test func warningsRequireReview() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(root: root)
        let session = DictationSession(sampleRate: 16_000, profileName: "General", vocabulary: "")
        try await store.create(session)
        try await store.appendAttempt(attempt("Partial", warnings: ["Token limit reached"]), to: session.id)
        #expect(try await store.read(session.id).state == .needsReview)
    }
    @Test func activeRecordingCannotBeDeleted() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(root: root)
        let session = DictationSession(sampleRate: 16_000, profileName: "General", vocabulary: "")
        try await store.create(session)
        await #expect(throws: (any Error).self) { try await store.delete(session.id) }
    }
    @Test func editingDoesNotMutateOriginalRecognition() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(root: root)
        let session = DictationSession(sampleRate: 16_000, profileName: "General", vocabulary: "")
        try await store.create(session)
        try await store.appendAttempt(attempt("original"), to: session.id)
        try await store.update(session.id) { $0.editedText = "edited" }
        let saved = try await store.read(session.id)
        #expect(saved.text == "edited")
        #expect(saved.attempts[0].text == "original")
    }
}

@Suite("Audio completeness") struct AudioTests {
    @Test func floatPCMIsLossless() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let samples: [Float] = [-1, -0.25, 0, 0.125, 1]
        let url = root.appendingPathComponent("audio.f32le")
        try PCMFile.encode(samples).write(to: url)
        #expect(try PCMFile.read(url) == samples)
    }
    @Test func aPartialFinalSampleDoesNotLoseEarlierAudio() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("audio.f32le")
        var data = PCMFile.encode([0.5, 0.25]); data.append(0xAB)
        try data.write(to: url)
        #expect(try PCMFile.read(url) == [0.5, 0.25])
    }
    @Test func normalDictationUsesASingleBatch() {
        #expect(BatchPlanner.ranges(samples: Array(repeating: 0, count: 40_000), sampleRate: 100) == [0..<40_000])
    }
    @Test func longRecordingsCoverEverySampleExactlyOnce() {
        let samples: [Float] = (0..<5234).map { Float($0 % 19) / 20 }
        let ranges = BatchPlanner.ranges(samples: samples, sampleRate: 10, maximumSeconds: 60)
        #expect(ranges.count > 1)
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == samples.count)
        #expect(ranges.reduce(0) { $0 + $1.count } == samples.count)
        for (a, b) in zip(ranges, ranges.dropFirst()) { #expect(a.upperBound == b.lowerBound) }
        #expect(ranges.allSatisfy { $0.count <= 600 && !$0.isEmpty })
    }
    @Test func tokenBudgetScalesWithDuration() {
        #expect(BatchPlanner.tokenBudget(seconds: 1200) > BatchPlanner.tokenBudget(seconds: 60))
        #expect(BatchPlanner.tokenBudget(seconds: 1200, multiplier: 4) <= 65_536)
    }
    @Test func exhaustedBudgetIsNotPresentedAsComplete() {
        #expect(!TranscriptChecks.warnings(text: "Hello", generatedTokens: 2048, tokenBudget: 2048).isEmpty)
    }
    @Test func cleanTranscriptHasNoWarning() {
        #expect(TranscriptChecks.warnings(text: "Use JSON in Blint.", generatedTokens: 8, tokenBudget: 2048).isEmpty)
    }
    @Test func emptyOutputIsFlagged() {
        #expect(!TranscriptChecks.warnings(text: "", generatedTokens: 0, tokenBudget: 2048).isEmpty)
    }
    @Test func wavHeaderAndPayloadAreValid() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("audio.f32le")
        let output = root.appendingPathComponent("audio.wav")
        let samples: [Float] = [0.1, -0.1, 0.2]
        try PCMFile.encode(samples).write(to: input)
        try PCMFile.exportWAV(from: input, sampleRate: 16000, to: output)
        let data = try Data(contentsOf: output)
        #expect(String(data: data.prefix(4), encoding: .ascii) == "RIFF")
        #expect(data.count == 44 + 12)
        #expect(data.suffix(12) == PCMFile.encode(samples))
    }
    @Test func exportCannotOverwriteRecoveryOriginal() throws {
        let url = URL(fileURLWithPath: "/tmp/audio.f32le")
        #expect(throws: (any Error).self) { try PCMFile.exportWAV(from: url, sampleRate: 16000, to: url) }
    }
}
