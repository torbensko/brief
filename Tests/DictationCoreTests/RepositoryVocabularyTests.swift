import Foundation
import Testing
@testable import DictationCore

@Suite("Automatic coding vocabulary")
struct RepositoryVocabularyTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func write(_ text: String, _ path: String, in root: URL) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
    @Test func allProjectsAndNestedPackagesShareOneContext() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write(#"{"name":"@acme/Blint","productName":"Blint","dependencies":{"react":"1","@tanstack/react-query":"1"}}"#, "blint/package.json", in: root)
        try write(#"{"name":"@acme/design-kit","devDependencies":{"typescript":"1"}}"#, "blint/packages/ui/package.json", in: root)
        try write("[project]\nname = 'Finch'\ndependencies = ['fastapi']", "finch/pyproject.toml", in: root)
        try write("print('ignored')", "finch/main.py", in: root)
        try write("# Finch Studio\nDescription", "finch/README.md", in: root)
        let scan = try RepositoryScanner.scan(path: root.path)
        #expect(scan.projects.count == 2)
        #expect(scan.names.contains("Blint"))
        #expect(scan.names.contains("@acme/design-kit"))
        #expect(scan.names.contains("Finch Studio"))
        #expect(scan.technologies.contains("FastAPI"))
        #expect(scan.technologies.contains("Python"))
        #expect(scan.technologies.contains("useInfiniteQuery"))
        var settings = AppSettings(); settings.repositoryVocabulary = scan
        #expect(settings.vocabularyContext.contains("Blint"))
        #expect(settings.vocabularyContext.contains("Finch"))
        #expect(settings.vocabularyContext.contains("TypeScript"))
        try settings.validate()
    }
    @Test func ignoresDependenciesHiddenFoldersAndSymlinks() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write(#"{"name":"RealProject"}"#, "real/package.json", in: root)
        for folder in ["node_modules", ".git", "build", "vendor", ".venv"] {
            try write(#"{"name":"ShouldNotAppear"}"#, "real/\(folder)/package.json", in: root)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("real/loop"), withDestinationURL: root)
        let scan = try RepositoryScanner.scan(path: root.path)
        #expect(scan.names.contains("RealProject"))
        #expect(!scan.names.contains("ShouldNotAppear"))
    }
    @Test func malformedMetadataIsVisibleAndOtherProjectsSurvive() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("{broken", "broken/package.json", in: root)
        try write("let package = Package(name: \"SpeechDesk\")", "speech/Package.swift", in: root)
        let scan = try RepositoryScanner.scan(path: root.path)
        #expect(scan.projects.count == 2)
        #expect(scan.names.contains("SpeechDesk"))
        #expect(scan.warnings.count == 1)
    }
    @Test func oldSettingsDecodeAndAllLegacyTermsArePreserved() throws {
        var original = AppSettings()
        original.globalTerms = "MyExtraWord"
        original.profiles = [VocabularyProfile(name: "Alpha", terms: "AlphaTerm"), VocabularyProfile(name: "Beta", terms: "BetaTerm")]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        json.removeValue(forKey: "repositoriesPath"); json.removeValue(forKey: "repositoryVocabulary")
        let settings = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(settings.effectiveRepositoriesPath == "~/repos")
        #expect(settings.vocabularyContext.contains("AlphaTerm"))
        #expect(settings.vocabularyContext.contains("BetaTerm"))
        #expect(settings.vocabularyContext.contains("MyExtraWord"))
        #expect(settings.vocabularyContext.contains("JSON"))
    }
    @Test func catalogSurvivesRestart() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write(#"{"name":"SavedName"}"#, "project/package.json", in: root)
        var settings = AppSettings(); settings.repositoryVocabulary = try RepositoryScanner.scan(path: root.path)
        let url = root.appendingPathComponent("settings.json")
        try SettingsFile.save(settings, to: url)
        #expect(try SettingsFile.load(from: url) == settings)
    }
    @Test func actualRepositoryScanWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["DICTATION_SCAN_TEST_ROOT"] else { return }
        var settings = AppSettings()
        settings.repositoryVocabulary = try RepositoryScanner.scan(path: path)
        try settings.validate()
        print("Repository scan: \(settings.repositoryVocabulary!.projects.count) repositories, \(settings.repositoryVocabulary!.names.count) names, \(settings.vocabularyContext.utf8.count) context bytes, \(settings.repositoryVocabulary!.warnings.count) notes")
    }
}
