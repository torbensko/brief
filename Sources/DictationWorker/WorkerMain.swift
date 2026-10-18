import Foundation
import AVFoundation
import DictationCore
import MLX
import MLXAudioSTT

/// A separate, long-lived process keeps model/GPU failures out of the recording app.
/// One request is processed at a time. No audio, vocabulary or transcript crosses a network.
@main
struct WorkerMain {
    static func main() async {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let library = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/mlx.metallib")
        if FileManager.default.fileExists(atPath: library.path) { GPU.metallib = library }
        if CommandLine.arguments.contains("--self-test") {
            let result = (MLXArray([Float(1), 2, 3]) * 2).sum().item(Float.self)
            guard result == 12 else { exit(1) }
            print("MLX Metal self-test passed")
            return
        }
        // Defensive flags for transitive libraries. The implementation below uses only
        // fromModelDirectory, never fromPretrained or a remote repository loader.
        setenv("HF_HUB_OFFLINE", "1", 1)
        setenv("TRANSFORMERS_OFFLINE", "1", 1)
        let engine = LocalEngine()
        while let line = readLine() {
            var requestID = UUID()
            do {
                let request = try JSONDecoder().decode(WorkerRequest.self, from: Data(line.utf8))
                requestID = request.id
                let response = try await engine.handle(request)
                emit(response)
            } catch {
                emit(WorkerResponse(id: requestID, success: false, message: error.localizedDescription))
            }
        }
    }
    static func emit(_ response: WorkerResponse) {
        do {
            let payload = try JSONEncoder().encode(response)
            var line = Data(WorkerResponse.prefix.utf8)
            line.append(payload); line.append(0x0A)
            try FileHandle.standardOutput.write(contentsOf: line)
        } catch { exit(2) }
    }
}

private final class LocalEngine {
    private var model: Qwen3ASRModel?
    private var loadedPath: String?
    func handle(_ request: WorkerRequest) async throws -> WorkerResponse {
        if request.operation == .unload {
            model = nil; loadedPath = nil; Memory.clearCache()
            return WorkerResponse(id: request.id, success: true)
        }
        let folder = URL(fileURLWithPath: request.modelDirectory, isDirectory: true)
        guard folder.path.hasPrefix("/"), !request.modelDirectory.isEmpty else {
            throw DictationError.message("Choose or download a local model in Settings first.")
        }
        try ModelDirectory.validate(folder)
        try Vocabulary.validate(request.context)
        if loadedPath != folder.path || model == nil {
            model = nil; loadedPath = nil; Memory.clearCache()
            model = try await Qwen3ASRModel.fromModelDirectory(folder)
            loadedPath = folder.path
        }
        guard request.operation == .transcribe else { return WorkerResponse(id: request.id, success: true) }
        guard let model, let path = request.audioPath, let sampleRate = request.sampleRate,
              sampleRate.isFinite, (8_000...384_000).contains(sampleRate) else {
            throw DictationError.message("The transcription request is missing valid audio metadata.")
        }
        let start = Date()
        let original = try PCMFile.read(URL(fileURLWithPath: path))
        guard original.allSatisfy(\.isFinite) else {
            throw DictationError.message("The saved audio contains invalid samples. Export and inspect the recording.")
        }
        let samples = try resample(original, from: sampleRate)
        let ranges = BatchPlanner.ranges(samples: samples, sampleRate: 16_000)
        guard !ranges.isEmpty else { throw DictationError.message("No saved audio to transcribe.") }
        var texts: [String] = []
        var warnings: [String] = []
        var generated = 0
        for (index, range) in ranges.enumerated() {
            let seconds = Double(range.count) / 16_000
            let budget = BatchPlanner.tokenBudget(seconds: seconds, multiplier: request.tokenBudgetMultiplier)
            let audio = MLXArray(Array(samples[range]))
            // Call the Qwen-specific overload: the generic STT interface discards context.
            // Each offline batch has its OWN budget; the upstream multi-batch budget is shared.
            let result = model.generate(audio: audio, maxTokens: budget, temperature: 0,
                                        context: request.context,
                                        language: request.language.isEmpty ? nil : request.language,
                                        chunkDuration: Float(seconds + 1), minChunkDuration: 1,
                                        repetitionPenalty: 1.0)
            texts.append(result.text)
            generated += result.generationTokens
            warnings += TranscriptChecks.warnings(text: result.text, generatedTokens: result.generationTokens,
                                                   tokenBudget: budget).map { "Part \(index + 1): \($0)" }
            Memory.clearCache()
        }
        let transcript = TranscriptAttempt(text: texts.joined(separator: "\n\n"),
            model: modelIdentity(folder), vocabulary: request.context, language: request.language,
            processingSeconds: Date().timeIntervalSince(start), audioSeconds: Double(original.count) / sampleRate,
            generationTokens: generated, warnings: warnings)
        return WorkerResponse(id: request.id, success: true, attempt: transcript)
    }
    private func modelIdentity(_ folder: URL) -> String {
        struct Receipt: Decodable { var repository: String; var revision: String }
        if let data = try? Data(contentsOf: folder.appendingPathComponent("installation.json")),
           let receipt = try? JSONDecoder().decode(Receipt.self, from: data) {
            return "\(receipt.repository)@\(receipt.revision)"
        }
        return "local:\(folder.lastPathComponent)"
    }
    private func resample(_ input: [Float], from rate: Double) throws -> [Float] {
        guard rate != 16_000 else { return input }
        guard input.count <= Int(UInt32.max),
              let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(input.count)),
              let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 16_000) else {
            throw DictationError.message("Could not prepare high-quality audio resampling.")
        }
        source.frameLength = AVAudioFrameCount(input.count)
        input.withUnsafeBufferPointer { source.floatChannelData![0].update(from: $0.baseAddress!, count: input.count) }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        var supplied = false
        var result: [Float] = []
        result.reserveCapacity(Int(Double(input.count) * 16_000 / rate) + 1024)
        var emptyPasses = 0
        while true {
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if supplied { inputStatus.pointee = .endOfStream; return nil }
                supplied = true; inputStatus.pointee = .haveData; return source
            }
            if let error { throw error }
            if status == .error { throw DictationError.message("The audio resampler failed.") }
            if output.frameLength > 0 {
                result.append(contentsOf: UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
                emptyPasses = 0
            } else { emptyPasses += 1 }
            if status == .endOfStream { break }
            if emptyPasses > 3 { throw DictationError.message("The resampler stalled before completing the recording.") }
            output.frameLength = 0
        }
        return result
    }
}
