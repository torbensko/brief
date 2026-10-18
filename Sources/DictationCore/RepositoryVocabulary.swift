import Foundation

public struct RepositoryProject: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var names: [String]
    public var technologies: [String]
}

public struct RepositoryVocabulary: Codable, Equatable, Sendable {
    public var root: String
    public var scannedAt: Date
    public var projects: [RepositoryProject]
    public var warnings: [String]
    public var names: [String] { Vocabulary.terms(projects.flatMap(\.names).joined(separator: "\n")) }
    public var technologies: [String] { Vocabulary.terms(projects.flatMap(\.technologies).joined(separator: "\n")).sorted() }
}

/// Reads local metadata as data; never executes manifests, scripts, or repository instructions.
public enum RepositoryScanner {
    public static let codingTerms = """
    API
    JSON
    YAML
    XML
    HTML
    CSS
    SQL
    GraphQL
    REST
    HTTP
    HTTPS
    URL
    SDK
    CLI
    Git
    GitHub
    branch
    commit
    pull request
    merge conflict
    rebase
    repository
    monorepo
    localhost
    frontend
    backend
    full stack
    async
    await
    callback
    middleware
    authentication
    authorization
    OAuth
    JWT
    environment variable
    dependency
    unit test
    integration test
    end-to-end test
    CI/CD
    Docker
    Kubernetes
    refactor
    lint
    typecheck
    schema
    migration
    webhook
    WebSocket
    regex
    null
    undefined
    boolean
    enum
    struct
    interface
    generic
    TypeScript
    JavaScript
    Python
    Swift
    Rust
    Go
    package.json
    README.md
    .gitignore
    """
    private static let ignored: Set<String> = ["node_modules", "vendor", "Pods", "Carthage", "build", "dist", "target", "DerivedData", "coverage", "venv", "env", "__pycache__", "Library", "cdk.out", "out", "tmp", "temp", "test-results", "playwright-report"]
    private static let languages = ["swift": "Swift", "ts": "TypeScript", "tsx": "TypeScript", "js": "JavaScript", "jsx": "React", "py": "Python", "rs": "Rust", "go": "Go", "rb": "Ruby", "kt": "Kotlin", "java": "Java", "cs": "C#", "cpp": "C++", "c": "C", "php": "PHP", "vue": "Vue", "svelte": "Svelte"]
    private static let frameworks: [(String, [String])] = [
        ("typescript", ["TypeScript", "tsconfig.json"]),
        ("react", ["React", "JSX", "useState", "useEffect", "useMemo", "useCallback"]),
        ("next", ["Next.js", "App Router", "server component"]),
        ("vue", ["Vue", "Nuxt"]), ("svelte", ["Svelte", "SvelteKit"]),
        ("angular", ["Angular", "RxJS"]), ("vite", ["Vite"]),
        ("tailwind", ["Tailwind CSS"]), ("prisma", ["Prisma"]),
        ("drizzle", ["Drizzle"]), ("supabase", ["Supabase", "PostgreSQL"]),
        ("convex", ["Convex"]), ("auth0", ["Auth0"]), ("clerk", ["Clerk"]),
        ("tanstack", ["TanStack Query", "useQuery", "useMutation", "useInfiniteQuery"]),
        ("react-query", ["TanStack Query", "useQuery", "useMutation", "useInfiniteQuery"]),
        ("express", ["Express", "Node.js"]), ("hono", ["Hono"]), ("zod", ["Zod"]),
        ("vitest", ["Vitest"]), ("jest", ["Jest"]), ("playwright", ["Playwright"]),
        ("electron", ["Electron"]), ("tauri", ["Tauri"]), ("expo", ["Expo", "React Native"]),
        ("django", ["Django"]), ("fastapi", ["FastAPI", "Pydantic"]),
        ("flask", ["Flask"]), ("pytest", ["pytest"]), ("pytorch", ["PyTorch"]),
        ("torch", ["PyTorch"]), ("numpy", ["NumPy"]), ("pandas", ["pandas"]),
        ("tokio", ["Tokio"]), ("axum", ["Axum"]), ("serde", ["Serde"]),
        ("mlx", ["MLX"]), ("swiftui", ["SwiftUI", "AppKit", "AVFoundation", "SwiftData"])
    ]

    public static func scan(path: String) throws -> RepositoryVocabulary {
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var projects: [RepositoryProject] = []
        var warnings: [String] = []
        var visited = 0
        for folder in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let info = try folder.resourceValues(forKeys: Set(keys))
            guard info.isDirectory == true, info.isSymbolicLink != true, !ignored.contains(folder.lastPathComponent) else { continue }
            var names: [String] = []
            var technologies: [String] = []
            var pending = [folder]
            while let directory = pending.popLast() {
                try Task.checkCancellation()
                let entries: [URL]
                do { entries = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) }
                catch { warnings.append("Could not read \(directory.lastPathComponent)."); continue }
                for file in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    visited += 1
                    guard visited <= 1_000_000 else { throw DictationError.message("This folder is too large to scan completely. Choose a folder containing your source repositories; the previous vocabulary has been kept.") }
                    guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
                    if values.isDirectory == true {
                        if !ignored.contains(file.lastPathComponent) { pending.append(file) }
                        continue
                    }
                    if let language = languages[file.pathExtension.lowercased()] { technologies.append(language) }
                    let filename = file.lastPathComponent
                    let metadata = ["package.json", "Cargo.toml", "pyproject.toml", "go.mod", "Package.swift", "composer.json", "requirements.txt", "Gemfile", "README.md"]
                    guard metadata.contains(filename) else { continue }
                    guard (values.fileSize ?? 0) <= 512_000 else { warnings.append("Skipped oversized metadata: \(filename) in \(directory.lastPathComponent)."); continue }
                    guard let text = try? String(contentsOf: file, encoding: .utf8) else { warnings.append("Could not read \(filename) in \(directory.lastPathComponent)."); continue }
                    if filename == "README.md" {
                        let projectMarkers = ["package.json", "Cargo.toml", "pyproject.toml", "go.mod", "Package.swift", "composer.json"]
                        guard directory == folder || entries.contains(where: { projectMarkers.contains($0.lastPathComponent) }) else { continue }
                        if let heading = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("# ") }) {
                            let title = String(heading.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                            if validName(title), !title.contains("["), !title.contains("<") { names.append(title) }
                        }
                        continue
                    }
                    technologies.append(filename)
                    if filename == "package.json" || filename == "composer.json" {
                        guard let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            warnings.append("Invalid \(filename) in \(directory.lastPathComponent)."); continue
                        }
                        for key in ["name", "productName"] {
                            if let name = json[key] as? String, validName(name) { names.append(name) }
                        }
                        var dependencies: [String] = []
                        for key in ["dependencies", "devDependencies", "peerDependencies", "require"] {
                            dependencies += (json[key] as? [String: Any]).map { Array($0.keys) } ?? []
                        }
                        technologies += terms(for: dependencies.joined(separator: " "))
                        if filename == "package.json" { technologies += ["Node.js", "npm"] }
                    } else {
                        // Literal declarations only; never evaluate Swift, Python, or shell code.
                        let pattern = filename == "Package.swift" ? #"name\s*:\s*"([^"\n]+)""# : #"(?m)^\s*name\s*=\s*["']([^"'\n]+)["']"#
                        if let regex = try? NSRegularExpression(pattern: pattern) {
                            let ns = text as NSString
                            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                                let name = ns.substring(with: match.range(at: 1))
                                if validName(name) { names.append(name) }
                            }
                        }
                        if filename == "go.mod", let line = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("module ") }) {
                            let name = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                            if validName(name) { names.append(name); names.append(URL(fileURLWithPath: name).lastPathComponent) }
                        }
                        technologies += terms(for: text)
                        if filename == "Package.swift" { technologies += ["Swift", "SwiftUI", "AppKit", "AVFoundation", "SwiftData", "Swift Package Manager"] }
                    }
                }
            }
            names.append(folder.lastPathComponent)
            projects.append(RepositoryProject(path: folder.path, names: Vocabulary.terms(names.joined(separator: "\n")), technologies: Vocabulary.terms(technologies.joined(separator: "\n")).sorted()))
        }
        return RepositoryVocabulary(root: root.path, scannedAt: Date(), projects: projects, warnings: warnings)
    }
    private static func validName(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 100 && !text.contains("\n") && !text.contains("<|") && !text.contains("|>")
    }
    private static func terms(for text: String) -> [String] {
        let lower = text.lowercased()
        return frameworks.filter { lower.contains($0.0) }.flatMap { $0.1 }
    }
}
