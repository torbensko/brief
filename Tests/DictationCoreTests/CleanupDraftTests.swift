import Foundation
import Testing
@testable import DictationCore

@Suite("Cleanup passage review") struct CleanupDraftTests {
    @Test func editAllowanceScalesWithWholeTranscriptLength() {
        let vocabulary = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet"]
        for count in [100, 1000, 5000] {
            let words = (0..<count).map { vocabulary[$0 % vocabulary.count] }
            let original = words.joined(separator: " ")
            let candidate = words.enumerated().map { $0.offset % 10 == 0 ? "omega" : $0.element }.joined(separator: " ")
            #expect(CleanupPolicy.rejection(original: original, candidate: candidate, protectedTerms: "", limits: CleanupLimits(editPercent: 20)) == nil)
            #expect(CleanupPolicy.rejection(original: original, candidate: candidate, protectedTerms: "", limits: CleanupLimits(editPercent: 19))?.contains("19% edit allowance") == true)
        }
    }
    @Test func rejectedQualifierChangeDoesNotEraseIndependentEdits() {
        let original = "The the quality is good. I think this might work. The the button is blue."
        let candidate = "The quality is good. This might work. The button is blue."
        var draft = CleanupDraft(original: original, candidate: candidate)
        var rejected = 0
        for index in draft.passages.indices where draft.passages[index].changed {
            if draft.rejection(at: index, protectedTerms: "", limits: CleanupLimits(enabled: false)) == nil {
                draft.accept(index)
            } else { rejected += 1 }
        }
        #expect(rejected == 1)
        #expect(draft.text == "The quality is good. I think this might work. The button is blue.")
    }
    @Test func semanticRejectionLeavesOnlyThatPassageUnedited() {
        var draft = CleanupDraft(original: "The the button is blue. That that file stays.", candidate: "The button is blue. That the file stays.")
        #expect(draft.passages.count == 2)
        draft.accept(0) // The reviewer approves only this passage.
        #expect(draft.text == "The button is blue. That that file stays.")
    }
    @Test func reviewSplittingDoesNotMultiplyTheMinimumAllowance() {
        let original = "alpha. bravo. charlie. delta. echo. foxtrot. golf. hotel."
        let candidate = "Alpha. Bravo. Charlie. Delta. Echo. Foxtrot. Golf. Hotel."
        var draft = CleanupDraft(original: original, candidate: candidate)
        var accepted = 0
        for index in draft.passages.indices where draft.passages[index].changed {
            if draft.rejection(at: index, protectedTerms: "", limits: CleanupLimits(editPercent: 0)) == nil {
                draft.accept(index); accepted += 1
            }
        }
        #expect(accepted == 3) // Three replacements use the shared six-edit floor.
        #expect(CleanupPolicy.rejection(original: original, candidate: draft.text, protectedTerms: "", limits: CleanupLimits(editPercent: 0)) == nil)
    }
    @Test func protectionsStillSpanPassageBoundaries() {
        let original = "Use `alpha. beta` here. Wait 15 minutes. Do not delete Blint."
        let candidate = "Use `alpha. gamma` here. Wait 5 minutes. Do delete Blint."
        let draft = CleanupDraft(original: original, candidate: candidate)
        for index in draft.passages.indices where draft.passages[index].changed {
            #expect(draft.rejection(at: index, protectedTerms: "Blint", limits: CleanupLimits(enabled: false)) != nil)
        }
        #expect(draft.text == original)
    }
    @Test func anchoredPassagesReconstructMergedAddedAndRemovedSentencesExactly() {
        for (original, candidate) in [
            ("Hello there. Another sentence. Last sentence.", "Hello there and another sentence. Last sentence."),
            ("First. Middle. Last.", "First. Last."),
            ("First. Last.", "First. Added. Last."),
            ("\nHi 👋.\n\n  café!", "Hi 👋!\n\nCafé!"),
            ("same", "same"), ("", "New text."), ("Remove this.", "")
        ] {
            let draft = CleanupDraft(original: original, candidate: candidate)
            #expect(draft.passages.map(\.original).joined() == original)
            #expect(draft.passages.map(\.candidate).joined() == candidate)
            #expect(draft.text == original)
        }
    }
    @Test func typographicApostrophesDoNotLookLikeLostNegation() {
        #expect(CleanupPolicy.rejection(original: "It doesn’t work. Don’t delete it.", candidate: "It doesn't work. Don't delete it.", protectedTerms: "") == nil)
        #expect(CleanupPolicy.rejection(original: "It doesn’t work.", candidate: "It does work.", protectedTerms: "") == "Cleanup changed a qualifier or condition.")
    }
}
