import Testing
@testable import DictationCore

@Suite("Verified insertion") struct InsertionVerificationTests {
    @Test func verifiesInsertionAtCursorAndSelectionReplacement() {
        let expected = InsertionVerification.expectedValue(before: "Hello world", location: 6, length: 5, text: "Blint")
        #expect(expected == "Hello Blint")
        #expect(InsertionVerification.confirms(expected: expected, actual: "Hello Blint"))
        #expect(!InsertionVerification.confirms(expected: expected, actual: "Hello world"))
        #expect(!InsertionVerification.confirms(expected: expected, actual: "Blint"))
    }
    @Test func usesAccessibilityUTF16OffsetsAndRejectsInvalidRanges() {
        #expect(InsertionVerification.expectedValue(before: "👋 ", location: 3, length: 0, text: "Blint") == "👋 Blint")
        #expect(InsertionVerification.expectedValue(before: "abc", location: 4, length: 0, text: "x") == nil)
        #expect(InsertionVerification.expectedValue(before: "abc", location: 1, length: 3, text: "x") == nil)
        #expect(InsertionVerification.expectedValue(before: "abc", location: -1, length: 0, text: "x") == nil)
    }
    @Test func unreadableFieldsCannotClaimSuccess() {
        #expect(!InsertionVerification.confirms(expected: nil, actual: nil))
        #expect(!InsertionVerification.confirms(expected: "Blint", actual: nil))
    }
}
