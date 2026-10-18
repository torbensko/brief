import Foundation
import CryptoKit
import DictationCore

/// The app's only network feature. Called only by the explicit Download Model button.
/// Metadata resolves once to an immutable revision; every subsequent download uses it.
actor ModelInstaller {
    struct ModelInfo: Decodable {
        struct Sibling: Decodable {
            struct LFS: Decodable { var sha256: String?; var size: Int64? }
            var rfilename: String
            var size: Int64?
            var blobId: String?
            var lfs: LFS?
        }
        var sha: String
        var siblings: [Sibling]
    }
    struct Receipt: Codable {
        var repository: String
        var revision: String
        var installedAt: Date
        var sha256: [String: String]
    }
    func install(under root: URL, progress: @escaping @Sendable (String) -> Void) async throws -> URL {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let repository = ModelDirectory.repository
        let metadataURL = URL(string: "https://huggingface.co/api/models/\(repository)?blobs=true")!
        progress("Fetching the model file manifest…")
        let (data, response) = try await session.data(from: metadataURL)
        try check(response)
        let info = try JSONDecoder().decode(ModelInfo.self, from: data)
        guard info.sha.count == 40, info.sha.allSatisfy(\.isHexDigit) else {
            throw DictationError.message("The model service returned an invalid revision.")
        }
        let files = info.siblings.filter {
            // Flat model files only; no Python code or remote executable model code.
            !$0.rfilename.contains("/") && !$0.rfilename.contains("..") &&
            (["json", "safetensors", "txt", "model"].contains(URL(fileURLWithPath: $0.rfilename).pathExtension)
             || ["README.md", "LICENSE"].contains($0.rfilename))
        }
        guard files.contains(where: { $0.rfilename.hasSuffix(".safetensors") }) else {
            throw DictationError.message("The model manifest contains no weights.")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = root.appendingPathComponent("Qwen3-ASR-1.7B-bf16-\(info.sha)")
        if fm.fileExists(atPath: destination.path) {
            try ModelDirectory.validate(destination)
            return destination
        }
        let staging = root.appendingPathComponent(".install-\(UUID())")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        var hashes: [String: String] = [:]
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let expectedBytes = file.size ?? file.lfs?.size
            let sizeText = expectedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
            progress("Downloading \(index + 1)/\(files.count): \(file.rfilename) \(sizeText)")
            let url = URL(string: "https://huggingface.co/\(repository)/resolve/\(info.sha)/\(file.rfilename)")!
            let (temporary, response) = try await session.download(from: url)
            try check(response)
            let target = staging.appendingPathComponent(file.rfilename)
            try fm.moveItem(at: temporary, to: target)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            let actualSize = (try fm.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
            if let expectedBytes, actualSize != expectedBytes {
                throw DictationError.message("Incomplete download: \(file.rfilename). Download again.")
            }
            progress("Verifying \(index + 1)/\(files.count): \(file.rfilename)…")
            let hash = try hashFile(target, length: actualSize)
            if let expected = file.lfs?.sha256, hash.sha256 != expected.lowercased() {
                throw DictationError.message("Checksum mismatch: \(file.rfilename). The model was not installed.")
            }
            if file.lfs == nil, let blobID = file.blobId, hash.gitBlob != blobID.lowercased() {
                throw DictationError.message("Git blob checksum mismatch: \(file.rfilename).")
            }
            hashes[file.rfilename] = hash.sha256
        }
        try ModelDirectory.validate(staging)
        let receipt = Receipt(repository: repository, revision: info.sha, installedAt: Date(), sha256: hashes)
        try JSONEncoder().encode(receipt).write(to: staging.appendingPathComponent("installation.json"), options: .atomic)
        try fm.moveItem(at: staging, to: destination)
        progress("Model installed. Recognition can now run offline.")
        return destination
    }
    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw DictationError.message("The model download failed (HTTP \(status)). No recording was uploaded.")
        }
    }
    private func hashFile(_ url: URL, length: Int64) throws -> (sha256: String, gitBlob: String) {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var sha256 = SHA256()
        var git = Insecure.SHA1()
        git.update(data: Data("blob \(length)\0".utf8))
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            sha256.update(data: data); git.update(data: data)
        }
        return (sha256.finalize().map { String(format: "%02x", $0) }.joined(),
                git.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
