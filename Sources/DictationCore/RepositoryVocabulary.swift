import Foundation

public struct RepositoryProject: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var names: [String]
}

public struct RepositoryVocabulary: Codable, Equatable, Sendable {
    public var schema: Int? = 2
    public var root: String
    public var scannedAt: Date
    public var projects: [RepositoryProject]
    public var warnings: [String]
    // Older caches contained dependencies and internal package names. Rescan before using them.
    public var names: [String] {
        guard schema == 2 else { return [] }
        return Vocabulary.terms(projects.flatMap(\.names).joined(separator: "\n"))
    }
}

/// A small personal dictionary of project names, not a source-code or dependency index.
public enum RepositoryScanner {
    public static func scan(path: String) throws -> RepositoryVocabulary {
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        let fm = FileManager.default
        let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        var projects: [RepositoryProject] = []
        var warnings: [String] = []
        var seenRoots = Set<String>()
        var seenNames = Set<String>()
        for folder in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try Task.checkCancellation()
            let info = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true,
                  !["node_modules", "build", "dist", "vendor"].contains(folder.lastPathComponent) else { continue }
            let project = canonicalRepository(folder)
            guard seenRoots.insert(project.path).inserted else { continue }
            var declared: String?
            for filename in ["package.json", "composer.json"] {
                guard let text = read(project.appendingPathComponent(filename)) else { continue }
                guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                    warnings.append("Could not read the project name in \(folder.lastPathComponent)/\(filename)."); continue
                }
                declared = (json["productName"] as? String) ?? (json["name"] as? String)
                if declared != nil { break }
            }
            if declared == nil {
                for filename in ["Package.swift", "Cargo.toml", "pyproject.toml"] {
                    guard let text = read(project.appendingPathComponent(filename)) else { continue }
                    let pattern = filename == "Package.swift" ? #"Package\s*\(\s*name\s*:\s*"([^"\n]+)""# : #"(?m)^\s*name\s*=\s*["']([^"'\n]+)["']"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                       let range = Range(match.range(at: 1), in: text) {
                        declared = String(text[range]); break
                    }
                }
            }
            // Use a short root README title for human spelling/capitalization, never nested headings.
            let heading = read(project.appendingPathComponent("README.md"))?
                .components(separatedBy: .newlines).first(where: { $0.hasPrefix("# ") }).map { String($0.dropFirst(2)) }
            let name = heading.flatMap(cleanName) ?? declared.flatMap(cleanName) ?? cleanName(project.lastPathComponent)
            guard let name, seenNames.insert(name.lowercased()).inserted else { continue }
            projects.append(RepositoryProject(path: project.path, names: [name]))
        }
        return RepositoryVocabulary(root: root.path, scannedAt: Date(), projects: projects, warnings: warnings)
    }

    private static func read(_ url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]),
              values.isSymbolicLink != true, (values.fileSize ?? 0) <= 512_000 else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func canonicalRepository(_ folder: URL) -> URL {
        // Git worktrees share a common .git directory; use the main project's metadata once.
        guard let pointer = read(folder.appendingPathComponent(".git")), pointer.hasPrefix("gitdir: ") else { return folder }
        let value = String(pointer.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
        let git = URL(fileURLWithPath: value, relativeTo: folder).standardizedFileURL
        guard let common = read(git.appendingPathComponent("commondir")) else { return folder }
        let directory = URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: git).standardizedFileURL
        guard directory.lastPathComponent == ".git" else { return folder }
        return directory.deletingLastPathComponent()
    }

    private static func cleanName(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" — ", " – ", " | ", " - ", ": "] {
            name = name.components(separatedBy: separator)[0]
        }
        if name.hasPrefix("@"), let component = name.split(separator: "/").last { name = String(component) }
        name = name.replacingOccurrences(of: #"(?i)(?:[ -]+v?\d+(?:\.\d+)*|[ -]+monorepo|[ -]+mono|[ -]+pipeline| projects repository)$"#, with: "", options: .regularExpression)
        guard !name.isEmpty, name.count <= 60, name.split(separator: " ").count <= 5,
              !name.contains("\n"), !name.contains("<"), !name.contains(">"), !name.contains("["), !name.contains("/"),
              !["readme", "overview", "getting started", "welcome", "documentation"].contains(name.lowercased()) else { return nil }
        return name
    }
}
