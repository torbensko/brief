import Foundation
import Testing
@testable import DictationCore

@Suite("Recent recovery") struct RecoveryTests {
    func session(_ age: Double, state: CaptureState = .ready) -> DictationSession {
        var value = DictationSession(date: Date(timeIntervalSince1970: 1_000 - age), sampleRate: 16_000, profileName: "test", vocabulary: "")
        value.state = state
        return value
    }
    @Test func defaultKeepsOnlyLatestSettledEntry() {
        let old = session(100), recent = session(10), active = session(0, state: .recording)
        #expect(RecoveryPolicy().expired(in: [old, active, recent]) == [old.id])
    }
    @Test func timeLimitExpiresPendingAndDeliveredButNeverActive() {
        var pending = session(301); pending.delivery = .pending
        var delivered = session(400); delivered.delivery = .inserted
        let recent = session(30), active = session(600, state: .transcribing)
        let expired = RecoveryPolicy(mode: .minutes, value: 5).expired(in: [pending, delivered, recent, active], now: Date(timeIntervalSince1970: 1_000))
        #expect(Set(expired) == Set([pending.id, delivered.id]))
    }
    @Test func longRecordingGetsRecoveryWindowAfterResultIsReady() {
        var value = session(900)
        value.attempts = [TranscriptAttempt(createdAt: Date(timeIntervalSince1970: 990), text: "Blint", model: "test", vocabulary: "Blint", processingSeconds: 5, audioSeconds: 900, generationTokens: 1)]
        #expect(RecoveryPolicy(mode: .minutes, value: 5).expired(in: [value], now: Date(timeIntervalSince1970: 1_000)).isEmpty)
    }
    @Test func failedAttemptCanKeepPreviousUsableTranscript() {
        let old = session(100), failed = session(0, state: .failed)
        #expect(RecoveryPolicy().expired(in: [old, failed], protecting: [old.id]).isEmpty)
    }
    @Test func pruningRemovesAudioAndMetadataTogether() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(root: root)
        let old = session(100), recent = session(0)
        try await store.create(old); try await store.create(recent)
        try Data([1,2,3,4]).write(to: store.audioURL(for: old.id))
        try await store.prune(RecoveryPolicy())
        #expect(!FileManager.default.fileExists(atPath: store.directory(for: old.id).path))
        #expect(try await store.snapshot().sessions.map(\.id) == [recent.id])
    }
    @Test func oldSettingsUseSmallDefaultAndPolicyRoundTrips() throws {
        let defaults = AppSettings()
        #expect(defaults.effectiveRecoveryPolicy == RecoveryPolicy(mode: .count, value: 1))
        var changed = defaults; changed.recoveryPolicy = RecoveryPolicy(mode: .minutes, value: 5)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(changed)) == changed)
        #expect(throws: (any Error).self) { try RecoveryPolicy(value: 0).validate() }
    }
}

@Suite("Coding disambiguation") struct CodingDisambiguationTests {
    @Test func selectedTypesAddFocusedSpellingHints() {
        let terms = CodingVocabulary.terms(for: ["TypeScript", "Swift"])
        #expect(terms.contains("JSON")); #expect(terms.contains("TypeScript")); #expect(terms.contains("SwiftUI"))
        #expect(!terms.contains("NumPy")); #expect(!terms.contains("React"))
        #expect(terms.count < 50)
    }
    @Test func detectorUsesFileTypesWithoutImportingDependencies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules/lib"), withIntermediateDirectories: true)
        try "".write(to: root.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try "{}".write(to: root.appendingPathComponent("tsconfig.json"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("node_modules/lib/test.py"), atomically: true, encoding: .utf8)
        #expect(CodingVocabulary.detect(in: root) == ["Swift", "TypeScript"])
    }
}
