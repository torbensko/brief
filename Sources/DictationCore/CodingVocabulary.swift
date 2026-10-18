import Foundation

/// Small spelling hints for spoken requirements, not a dependency or symbol inventory.
public enum CodingVocabulary {
    public static let common = ["JSON", "API", "UI", "URL", "SQL", "YAML", "HTML", "CSS", "OAuth", "Git", "GitHub", "frontend", "backend", "webhook", "schema", "enum", "boolean", "nullable", "async"]
    public static func terms(for types: [String]) -> [String] {
        var terms = common
        for type in types.sorted() {
            switch type {
            case "TypeScript": terms += ["TypeScript", "JavaScript", "TSX", "JSX", "Promise", "undefined"]
            case "JavaScript": terms += ["JavaScript", "JSX", "Promise", "undefined"]
            case "Swift": terms += ["Swift", "SwiftUI", "AppKit", "Codable", "Sendable", "struct", "optional"]
            case "Python": terms += ["Python", "pytest", "NumPy", "kwargs"]
            case "Rust": terms += ["Rust", "Cargo", "trait", "struct"]
            case "Go": terms += ["Go", "goroutine", "struct"]
            default: break
            }
        }
        return Vocabulary.terms(terms.joined(separator: "\n"))
    }
    public static func detect(in root: URL) -> [String] {
        let fm = FileManager.default
        var found = Set<String>()
        var pending: [(URL, Int)] = [(root, 0)]
        var visited = 0
        let ignored: Set<String> = ["node_modules", "vendor", "build", "dist", "target", "Pods", "cdk.out", "coverage", "venv"]
        while let (folder, depth) = pending.popLast(), visited < 5_000 {
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { continue }
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                visited += 1
                guard visited <= 5_000, let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { continue }
                if values.isDirectory == true {
                    if file.pathExtension == "xcodeproj" { found.insert("Swift") }
                    if depth < 3 && !ignored.contains(file.lastPathComponent) { pending.append((file, depth + 1)) }
                } else {
                    switch file.pathExtension {
                    case "ts", "tsx": found.insert("TypeScript")
                    case "js", "jsx": found.insert("JavaScript")
                    case "swift": found.insert("Swift")
                    case "py": found.insert("Python")
                    case "rs": found.insert("Rust")
                    case "go": found.insert("Go")
                    default: break
                    }
                    switch file.lastPathComponent {
                    case "tsconfig.json": found.insert("TypeScript")
                    case "pyproject.toml": found.insert("Python")
                    case "Cargo.toml": found.insert("Rust")
                    case "go.mod": found.insert("Go")
                    default: break
                    }
                }
            }
        }
        return found.sorted()
    }
}
