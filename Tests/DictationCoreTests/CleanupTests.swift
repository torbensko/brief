import Foundation
import Testing
@testable import DictationCore

@Suite("Conservative wording cleanup") struct CleanupTests {
    @Test func cleanupBudgetScalesWithRecordingDuration() {
        for (duration, budget) in [(10.0, 5.0), (30, 5), (60, 6), (120, 12), (200, 20), (600, 20)] {
            #expect(CleanupPolicy.waitBudget(audioSeconds: duration) == budget)
        }
        for invalid in [0.0, -1, Double.nan, Double.infinity] {
            #expect(CleanupPolicy.waitBudget(audioSeconds: invalid) == 5)
        }
    }
    @Test func ordinaryLongDictationsAreEligibleForCleanup() {
        #expect(!CleanupPolicy.shouldAttempt(" \n"))
        #expect(CleanupPolicy.shouldAttempt(String(repeating: "a", count: 1201)))
        #expect(CleanupPolicy.shouldAttempt(String(repeating: "a", count: 8000)))
        #expect(!CleanupPolicy.shouldAttempt(String(repeating: "a", count: 8001)))
    }
    @Test func rejectsLostQualifiersNumbersNamesAndLiterals() {
        for (original, edited) in [
            ("I think we should keep Blint.", "We should keep Blint."),
            ("Do not delete this file.", "Do delete this file."),
            ("It is not not working.", "It is not working."),
            ("Wait 15 minutes before retrying.", "Wait 5 minutes before retrying."),
            ("Please update Blint today.", "Please update Blink today."),
            ("Read package.json first.", "Read package.swift first."),
            ("Use `foo_bar` here.", "Use `fooBar` here."),
            ("I really need this today.", "I need this today."),
            ("It is very, very slow.", "It is very slow."),
            ("Please, please send it.", "Please send it."),
            ("Keep this as it is.", "")
        ] {
            #expect(CleanupPolicy.rejection(original: original, candidate: edited, protectedTerms: "Blint, JSON") != nil, "\(original) → \(edited)")
        }
    }
    @Test func allowsSmallChangesAndPreservesLegitimateRepetition() {
        #expect(CleanupPolicy.rejection(original: "The the quality is good.", candidate: "The quality is good.", protectedTerms: "") == nil)
        #expect(CleanupPolicy.rejection(original: "I think, I think we should keep Blint.", candidate: "I think we should keep Blint.", protectedTerms: "Blint") == nil)
        #expect(CleanupPolicy.rejection(original: "It is very, very slow.", candidate: "It is very, very slow.", protectedTerms: "") == nil)
    }
    @Test func diffCanReconstructBothVersionsIncludingUnicodeAndWhitespace() {
        for (original, revised) in [
            ("The the quality is good.", "The quality is good."),
            ("i like Blint", "I like Blint."),
            ("Hi 👋\n\n  café", "Hi 👋,\n\ncafé!"),
            ("", "Hello"), ("Hello", ""), ("same", "same"),
            ("a b c", "c b a")
        ] {
            let parts = TranscriptDiff.parts(original: original, revised: revised)
            #expect(parts.filter { $0.kind != .added }.map(\.text).joined() == original)
            #expect(parts.filter { $0.kind != .removed }.map(\.text).joined() == revised)
        }
    }
    @Test func oldSettingsStayOptInAndOriginalSurvivesPersistence() throws {
        #expect(!(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(AppSettings()))).effectiveTidyWording)
        var session = DictationSession(sampleRate: 16000, profileName: "Test", vocabulary: "")
        session.cleanup = TranscriptCleanup(original: "The the quality is good.", text: "The quality is good.", model: "test")
        let restored = try JSONDecoder().decode(DictationSession.self, from: JSONEncoder().encode(session))
        #expect(restored.text == "The quality is good.")
        #expect(restored.cleanup?.original == "The the quality is good.")
        session.editedText = "Manual edit"
        #expect(session.text == "Manual edit")
    }
    @Test func timedRecoveryStartsWhenCleanupFinishesAndCopyDoesNotExtendIt() {
        let now = Date()
        var session = DictationSession(sampleRate: 16000, profileName: "Test", vocabulary: "")
        session.state = .ready
        session.attempts = [TranscriptAttempt(createdAt: now.addingTimeInterval(-100), text: "The the file", model: "test", vocabulary: "", processingSeconds: 0, audioSeconds: 0, generationTokens: 0)]
        session.cleanup = TranscriptCleanup(original: "The the file", text: "The file", model: "test", createdAt: now)
        let policy = RecoveryPolicy(mode: .minutes, value: 1)
        #expect(policy.expired(in: [session], now: now.addingTimeInterval(59)).isEmpty)
        session.delivery = .copied
        session.updatedAt = now.addingTimeInterval(59)
        #expect(policy.expired(in: [session], now: now.addingTimeInterval(61)) == [session.id])
    }
    @Test func retryClearsPriorCleanupAndManualEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(root: root)
        var session = DictationSession(sampleRate: 16000, profileName: "Test", vocabulary: "")
        session.cleanup = TranscriptCleanup(original: "old old", text: "old", model: "test")
        session.editedText = "manual"
        try await store.create(session)
        try await store.appendAttempt(TranscriptAttempt(text: "New result", model: "test", vocabulary: "", processingSeconds: 0, audioSeconds: 0, generationTokens: 0), to: session.id)
        let saved = try await store.snapshot().sessions[0]
        #expect(saved.cleanup == nil)
        #expect(saved.text == "New result")
    }
}
