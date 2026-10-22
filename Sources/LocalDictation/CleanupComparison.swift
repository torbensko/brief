import SwiftUI
import DictationCore

struct CleanupComparison: View {
    let cleanup: TranscriptCleanup
    var body: some View { Text(attributed).accessibilityLabel("Wording edits. " + TranscriptDiff.parts(original: cleanup.original, revised: cleanup.text).map { part in
        switch part.kind { case .unchanged: return part.text; case .added: return " Added: " + part.text; case .removed: return " Removed: " + part.text }
    }.joined()) }
    private var attributed: AttributedString {
        var result = AttributedString()
        for part in TranscriptDiff.parts(original: cleanup.original, revised: cleanup.text) {
            var span = AttributedString(part.text)
            switch part.kind {
            case .unchanged: break
            case .added: span.backgroundColor = .green.opacity(0.2); span.underlineStyle = .single
            case .removed: span.backgroundColor = .orange.opacity(0.16); span.strikethroughStyle = .single
            }
            result.append(span)
        }
        return result
    }
}
