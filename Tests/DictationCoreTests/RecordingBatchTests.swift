import Foundation
import Testing
@testable import DictationCore

@Suite("Overlapping recordings") struct RecordingBatchTests {
    private func passedSteps(after stages: [RecordingBatch.Stage], starting: RecordingBatch.Stage = .preparing) throws -> [Int] {
        var batch = RecordingBatch()
        let id = UUID()
        batch.begin(id, stage: starting)
        for stage in stages { batch.update(id, stage: stage) }
        let item = try #require(batch.items.first)
        return (0..<4).filter { item.stage.hasPassed($0, reachedStep: item.reachedStep) }
    }
    @Test func onlyStagesThatRanAreMarkedPassed() throws {
        // A full run ticks everything before Complete, which is shown as current.
        #expect(try passedSteps(after: [.recording, .saving, .queued, .transcribing, .cleaning, .complete]) == [0, 1, 2])
        // Tidy wording off, or no speech: cleanup never ran.
        #expect(try passedSteps(after: [.recording, .saving, .queued, .transcribing, .complete]) == [0, 1])
        // Audio only, or cancelled while queued: recording finished, nothing else ran.
        #expect(try passedSteps(after: [.recording, .saving, .stopped]) == [0])
        #expect(try passedSteps(after: [.recording, .saving, .queued, .stopped]) == [0])
        // Cancelled before the microphone was ready: nothing finished.
        #expect(try passedSteps(after: [.stopped]) == [])
        // A failure does not tick the step it interrupted.
        #expect(try passedSteps(after: [.recording, .saving, .transcribing, .failed]) == [0])
        #expect(try passedSteps(after: [.recording, .saving, .transcribing, .cleaning, .failed]) == [0, 1])
        // Retries start from saved audio.
        #expect(try passedSteps(after: [.transcribing], starting: .queued) == [0])
    }
    @Test func stoppedRecordingsDoNotKeepTheBatchActive() {
        var batch = RecordingBatch()
        let a = UUID()
        batch.begin(a)
        batch.update(a, stage: .stopped)
        #expect(!batch.isActive)
    }
    @Test func chainedOverlapIncludesRecordingQueueAndCleanup() {
        var batch = RecordingBatch()
        let a = UUID(), b = UUID(), c = UUID()
        let group = batch.begin(a)
        batch.update(a, stage: .cleaning)
        #expect(batch.begin(b) == group)
        batch.update(b, stage: .recording)
        batch.update(a, stage: .complete)
        #expect(batch.begin(c) == group)
        batch.update(b, stage: .queued)
        batch.update(c, stage: .complete)
        #expect(batch.isActive)
        #expect(batch.items.map(\.id) == [a, b, c])
        batch.update(b, stage: .complete)
        #expect(!batch.isActive)
        let d = UUID()
        #expect(batch.begin(d) != group)
        #expect(batch.items.map(\.id) == [d])
    }
    @Test func resultsAreAssembledInCaptureOrderAndCleanupReplacesOnlyItsMember() {
        var batch = RecordingBatch()
        let a = UUID(), b = UUID(), c = UUID()
        batch.begin(a); batch.begin(b); batch.begin(c)
        batch.publish("Third", for: c)
        batch.publish("First first", for: a)
        #expect(batch.clipboardText == "First first\n\nThird")
        batch.publish("Second", for: b)
        batch.publish("First", for: a)
        #expect(batch.clipboardText == "First\n\nSecond\n\nThird")
        let repeated = batch.publish("First", for: a)
        #expect(!repeated)
    }
    @Test func takingOriginalPinsOnlyThatRecording() {
        var batch = RecordingBatch()
        let a = UUID(), b = UUID()
        batch.begin(a); batch.begin(b)
        batch.publish("Original A", for: a, chooseOriginal: true)
        let replaced = batch.publish("Cleaned A", for: a)
        #expect(!replaced)
        batch.publish("Original B", for: b)
        batch.publish("Cleaned B", for: b)
        #expect(batch.clipboardText == "Original A\n\nCleaned B")
    }
    @Test func failedAndEmptyMembersDoNotLoseUsableTextOrKeepGroupAlive() {
        var batch = RecordingBatch()
        let a = UUID(), b = UUID()
        batch.begin(a); batch.begin(b)
        batch.publish("Keep this", for: a)
        batch.publish(" \n", for: b)
        batch.update(a, stage: .complete)
        batch.update(b, stage: .failed)
        #expect(batch.clipboardText == "Keep this")
        #expect(!batch.isActive)
        batch.begin(UUID())
        #expect(batch.clipboardText.isEmpty)
        batch.publish("Late stale result", for: a)
        #expect(batch.clipboardText.isEmpty)
    }
    @Test func longChainHasNoFixedRecordingLimit() {
        var batch = RecordingBatch()
        let first = UUID(); let group = batch.begin(first)
        for n in 1...150 {
            let id = UUID()
            #expect(batch.begin(id) == group)
            batch.publish("Part \(n)", for: id)
            batch.update(id, stage: .complete)
        }
        #expect(batch.items.count == 151)
        batch.update(first, stage: .complete)
        #expect(!batch.isActive)
        #expect(batch.clipboardText.components(separatedBy: "\n\n").count == 150)
    }
    @Test func expiryRemovesSettledTextButProtectsLiveWork() {
        var batch = RecordingBatch()
        let a = UUID(), b = UUID()
        batch.begin(a); batch.begin(b)
        batch.publish("Expired text", for: a)
        batch.update(a, stage: .complete)
        batch.removeExpired([a, b])
        #expect(batch.items.map(\.id) == [b])
        #expect(batch.clipboardText.isEmpty)
        #expect(batch.isActive)
    }
    @Test func recoveryCountKeepsWholeGroupsAndLegacyEntries() throws {
        func session(_ age: Double, group: UUID? = nil) -> DictationSession {
            var session = DictationSession(date: Date(timeIntervalSince1970: 1000 - age), sampleRate: 16000, profileName: "Test", vocabulary: "")
            session.state = .ready; session.clipboardGroupID = group
            return session
        }
        let group = UUID()
        let a = session(10, group: group), b = session(5, group: group), old = session(20)
        #expect(RecoveryPolicy().expired(in: [a, old, b]) == [old.id])
        #expect(RecoveryPolicy(value: 2).expired(in: [a, old, b]).isEmpty)
        #expect(try JSONDecoder().decode(DictationSession.self, from: JSONEncoder().encode(a)).clipboardGroupID == group)
        #expect(try JSONDecoder().decode(DictationSession.self, from: JSONEncoder().encode(old)).clipboardGroupID == nil)
        #expect(Set(RecoveryPolicy(mode: .minutes, value: 1).expired(in: [a, b], now: Date(timeIntervalSince1970: 1100))) == [a.id, b.id])
    }
}
