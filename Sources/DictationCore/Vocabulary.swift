import Foundation

public enum Vocabulary {
    public static func terms(_ input: String) -> [String] {
        var seen = Set<String>()
        return input.components(separatedBy: .newlines).compactMap { raw in
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, seen.insert(term.lowercased()).inserted else { return nil }
            return term
        }
    }
    public static func context(global: String, project: String) -> String {
        // Give project-specific spellings precedence. This is recognition context,
        // not a post-transcription replacement dictionary or rewriting instruction.
        terms(project + "\n" + global).joined(separator: ", ")
    }
    public static func validate(_ context: String) throws {
        guard context.utf8.count <= 16_384 else {
            throw DictationError.message("Vocabulary is too large. The combined coding vocabulary must fit within 16 KB. Reduce extra terms or choose a smaller repositories folder; no terms were silently dropped.")
        }
        guard !context.contains("<|"), !context.contains("|>") else {
            throw DictationError.message("Vocabulary cannot contain model control-token delimiters.")
        }
    }
}
