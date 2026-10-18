import Foundation

public enum PCMFile {
    public static func read(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty else { throw DictationError.message("This recording has no saved audio samples.") }
        let count = data.count / 4 // A crash may leave one incomplete sample; ignore only those trailing bytes.
        return data.withUnsafeBytes { bytes in
            (0..<count).map { index in
                Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)))
            }
        }
    }
    public static func encode(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 4)
        for sample in samples {
            var bits = sample.bitPattern.littleEndian
            Swift.withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }
    /// IEEE Float WAV is useful for listening/export without altering the recovery original.
    public static func exportWAV(from source: URL, sampleRate: Double, to output: URL) throws {
        guard source.standardizedFileURL != output.standardizedFileURL else {
            throw DictationError.message("The export must not overwrite the recovery recording.")
        }
        let size = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
        let bytes = size - size % 4
        guard bytes > 0, bytes <= Int64(UInt32.max) - 36,
              sampleRate.isFinite, sampleRate >= 8_000, sampleRate <= 384_000 else {
            throw DictationError.message("The recording cannot be exported as a standard WAV file.")
        }
        var header = Data()
        func text(_ value: String) { header.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { var v = value.littleEndian; Swift.withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var v = value.littleEndian; Swift.withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(bytes) + 36); text("WAVEfmt "); u32(16)
        u16(3); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 4); u16(4); u16(32)
        text("data"); u32(UInt32(bytes))
        // Atomic export: an error must not leave a plausible but incomplete WAV file.
        let temp = output.deletingLastPathComponent().appendingPathComponent(".\(UUID()).wav")
        guard FileManager.default.createFile(atPath: temp.path, contents: header, attributes: [.posixPermissions: 0o600]) else {
            throw DictationError.message("Could not create the audio export.")
        }
        defer { try? FileManager.default.removeItem(at: temp) }
        let input = try FileHandle(forReadingFrom: source)
        let out = try FileHandle(forWritingTo: temp)
        defer { try? input.close(); try? out.close() }
        try out.seekToEnd()
        var remaining = bytes
        while remaining > 0 {
            guard let chunk = try input.read(upToCount: Int(min(1_048_576, remaining))), !chunk.isEmpty else {
                throw DictationError.message("The recording ended unexpectedly during export.")
            }
            try out.write(contentsOf: chunk); remaining -= Int64(chunk.count)
        }
        try out.synchronize(); try out.close()
        if FileManager.default.fileExists(atPath: output.path) {
            _ = try FileManager.default.replaceItemAt(output, withItemAt: temp)
        } else { try FileManager.default.moveItem(at: temp, to: output) }
    }
}

public enum BatchPlanner {
    /// Offline-only partitioning. Every sample belongs to exactly one batch.
    /// Normal dictations <=20 minutes are passed as one complete recording.
    public static func ranges(samples: [Float], sampleRate: Int, maximumSeconds: Int = 1200) -> [Range<Int>] {
        guard !samples.isEmpty, sampleRate > 0, maximumSeconds > 0 else { return [] }
        let maximum = sampleRate * maximumSeconds
        var output: [Range<Int>] = []
        var start = 0
        while start < samples.count {
            var end = min(start + maximum, samples.count)
            if end < samples.count {
                // Search only BEFORE the limit, so a low-energy cut cannot exceed it.
                let window = max(1, sampleRate / 10)
                let searchStart = max(start + maximum / 2, end - 5 * sampleRate)
                if searchStart + window < end {
                    var best = Double.infinity
                    for candidate in stride(from: searchStart, to: end - window, by: window) {
                        let energy = samples[candidate..<(candidate + window)].reduce(0.0) { $0 + Double($1) * Double($1) }
                        if energy < best { best = energy; end = candidate + window / 2 }
                    }
                }
            }
            output.append(start..<end)
            start = end
        }
        return output
    }
    public static func tokenBudget(seconds: Double, multiplier: Int = 1) -> Int {
        let safe = seconds.isFinite ? max(0, min(1200, seconds)) : 1200
        return min(65_536, max(2048, Int(ceil(safe * 16))) * max(1, min(4, multiplier)))
    }
}

public enum TranscriptChecks {
    public static func warnings(text: String, generatedTokens: Int, tokenBudget: Int) -> [String] {
        var messages: [String] = []
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("The recogniser returned no text. Listen to the saved audio and retry.")
        }
        if generatedTokens >= tokenBudget {
            messages.append("The output token limit was reached. This transcript may be incomplete; retry with a larger budget.")
        }
        let words = text.lowercased().split(whereSeparator: { $0.isWhitespace })
        if words.count >= 12 && Set(words.suffix(12)).count <= 3 {
            messages.append("Repetitive output detected. Review the saved audio for a possible recognition loop.")
        }
        return messages
    }
}
