import Foundation
import Testing
@testable import DictationCore

@Suite("Editor delivery") struct DeliveryFeedbackTests {
    @Test func recognizedTextEditorsDoNotRequireCursorRange() {
        #expect(TextFieldEligibility.allows(role: "AXTextArea", enabled: true, editable: nil, secure: false))
        #expect(TextFieldEligibility.allows(role: "AXTextField", enabled: true, editable: true, secure: false))
    }
    @Test func unknownReadonlyDisabledAndSecureFieldsRemainBlocked() {
        #expect(!TextFieldEligibility.allows(role: "AXGroup", enabled: true, editable: true, secure: false))
        #expect(!TextFieldEligibility.allows(role: "AXTextArea", enabled: true, editable: false, secure: false))
        #expect(!TextFieldEligibility.allows(role: "AXTextArea", enabled: false, editable: true, secure: false))
        #expect(!TextFieldEligibility.allows(role: "AXTextField", enabled: true, editable: true, secure: true))
    }
    @Test func copyingDoesNotErasePersistedDeliveryExplanation() throws {
        var session = DictationSession(sampleRate: 16_000, profileName: "test", vocabulary: "")
        session.deliveryNote = "Not inserted: destination changed."
        session.delivery = .copied
        let restored = try JSONDecoder().decode(DictationSession.self, from: JSONEncoder().encode(session))
        #expect(restored.deliveryNote == session.deliveryNote)
        #expect(restored.delivery == .copied)
    }
}
