import Foundation
import Testing
@testable import DictationCore

@Suite("Conservative wording cleanup") struct CleanupTests {
    @Test func configurableEditAllowanceAcceptsBoundaryAndRejectsAboveIt() {
        let original = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango"
        let words = original.split(separator: " ").map(String.init)
        let boundary = (Array(repeating: "edited", count: 8) + words.dropFirst(8)).joined(separator: " ")
        let above = (Array(repeating: "edited", count: 9) + words.dropFirst(9)).joined(separator: " ")
        #expect(CleanupPolicy.rejection(original: original, candidate: boundary, protectedTerms: "") == nil)
        #expect(CleanupPolicy.rejection(original: original, candidate: above, protectedTerms: "")?.contains("80% edit") == true)
        #expect(CleanupPolicy.rejection(original: original, candidate: boundary, protectedTerms: "", limits: CleanupLimits(editPercent: 40)) != nil)
        #expect(CleanupPolicy.rejection(original: original, candidate: above, protectedTerms: "", limits: CleanupLimits(editPercent: 90)) == nil)
    }
    @Test func configurableGrowthAllowanceAndShortMessageFloor() {
        let original = String(repeating: "a", count: 200)
        #expect(CleanupPolicy.rejection(original: original, candidate: String(repeating: "b", count: 260), protectedTerms: "") == nil)
        #expect(CleanupPolicy.rejection(original: original, candidate: String(repeating: "b", count: 261), protectedTerms: "")?.contains("30% text growth") == true)
        #expect(CleanupPolicy.rejection(original: original, candidate: String(repeating: "b", count: 280), protectedTerms: "", limits: CleanupLimits(growthPercent: 40)) == nil)
        #expect(CleanupPolicy.rejection(original: "a", candidate: String(repeating: "b", count: 31), protectedTerms: "", limits: CleanupLimits(editPercent: 0, growthPercent: 0)) == nil)
        #expect(throws: DictationError.self) { try CleanupLimits(editPercent: -1).validate() }
        #expect(throws: DictationError.self) { try CleanupLimits(growthPercent: -1).validate() }
    }
    @Test func disablingSizeLimitsStillProtectsMeaning() {
        let unlimited = CleanupLimits(enabled: false)
        #expect(CleanupPolicy.rejection(original: "hello", candidate: String(repeating: "hello ", count: 30), protectedTerms: "", limits: unlimited) == nil)
        #expect(CleanupPolicy.rejection(original: "Do not delete Blint.", candidate: "Delete Blint.", protectedTerms: "Blint", limits: unlimited) == "Cleanup changed a qualifier or condition.")
    }
    @Test func limitsMigrateAndTravelToWorker() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let legacy = try decoder.decode(AppSettings.self, from: encoder.encode(AppSettings()))
        #expect(legacy.effectiveCleanupLimits == CleanupLimits(editPercent: 80, growthPercent: 30))
        var custom = legacy
        custom.cleanupLimits = CleanupLimits(editPercent: 120, growthPercent: 45, enabled: false)
        let restored = try decoder.decode(AppSettings.self, from: encoder.encode(custom))
        #expect(restored.effectiveCleanupLimits == custom.cleanupLimits)
        let request = WorkerRequest(operation: .cleanup, modelDirectory: "test", cleanupLimits: restored.effectiveCleanupLimits)
        let decoded = try decoder.decode(WorkerRequest.self, from: encoder.encode(request))
        #expect(decoded.cleanupLimits == custom.cleanupLimits)
        #expect(CleanupPolicy.rejection(original: "Wait 15 minutes.", candidate: "Wait 5 minutes.", protectedTerms: "", limits: decoded.cleanupLimits!) == "Cleanup changed a number.")
    }
    @Test func cleanupBudgetScalesWithRecordingDuration() {
        for (duration, budget) in [(1.5, 0.15), (10, 1), (30, 3), (60, 6), (120, 12), (300, 30), (600, 60), (3600, 360)] {
            #expect(CleanupPolicy.waitBudget(audioSeconds: duration) == budget)
        }
        for invalid in [0.0, -1, Double.nan, Double.infinity] {
            #expect(CleanupPolicy.waitBudget(audioSeconds: invalid) == 0)
        }
    }
    @Test func ordinaryLongDictationsAreEligibleForCleanup() {
        #expect(!CleanupPolicy.shouldAttempt(" \n"))
        #expect(CleanupPolicy.shouldAttempt(String(repeating: "a", count: 1201)))
        #expect(CleanupPolicy.shouldAttempt(String(repeating: "a", count: 8000)))
        #expect(CleanupPolicy.shouldAttempt(String(repeating: "a", count: 8001)))
        #expect(CleanupPolicy.shouldAttempt(String(repeating: "a", count: 20000)))
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
