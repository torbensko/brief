import Foundation

public struct WorkerRequest: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case load, transcribe, unload }
    public var id: UUID
    public var operation: Operation
    public var modelDirectory: String
    public var audioPath: String?
    public var sampleRate: Double?
    public var context: String
    public var language: String
    public var tokenBudgetMultiplier: Int
    public init(id: UUID = UUID(), operation: Operation, modelDirectory: String,
                audioPath: String? = nil, sampleRate: Double? = nil, context: String = "",
                language: String = "English", tokenBudgetMultiplier: Int = 1) {
        self.id = id; self.operation = operation; self.modelDirectory = modelDirectory
        self.audioPath = audioPath; self.sampleRate = sampleRate; self.context = context
        self.language = language; self.tokenBudgetMultiplier = tokenBudgetMultiplier
    }
}
public struct WorkerResponse: Codable, Sendable {
    public static let prefix = "LOCALDICTATION:"
    public var id: UUID
    public var success: Bool
    public var message: String?
    public var attempt: TranscriptAttempt?
    public init(id: UUID, success: Bool, message: String? = nil, attempt: TranscriptAttempt? = nil) {
        self.id = id; self.success = success; self.message = message; self.attempt = attempt
    }
}

public enum ModelDirectory {
    public static let repository = "mlx-community/Qwen3-ASR-1.7B-bf16"
    public static func validate(_ url: URL) throws {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])
        let names = Set(files.map(\.lastPathComponent))
        guard names.contains("config.json"), names.contains("tokenizer_config.json") else {
            throw DictationError.message("The model folder is missing config.json or tokenizer_config.json.")
        }
        guard names.contains("tokenizer.json") || (names.contains("vocab.json") && names.contains("merges.txt")) else {
            throw DictationError.message("The model tokenizer is incomplete.")
        }
        let weights = files.filter { $0.pathExtension == "safetensors" }
        guard !weights.isEmpty else { throw DictationError.message("The model folder contains no safetensors weights.") }
        for weight in weights {
            let size = try weight.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 1024 else { throw DictationError.message("\(weight.lastPathComponent) is incomplete or a Git LFS pointer.") }
        }
        if names.contains("model.safetensors.index.json") {
            struct Index: Decodable { var weight_map: [String: String] }
            let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: url.appendingPathComponent("model.safetensors.index.json")))
            guard Set(index.weight_map.values).isSubset(of: names) else {
                throw DictationError.message("One or more model weight shards are missing.")
            }
        }
    }
}
