import AVFoundation
import Foundation
import DictationCore

struct RecordingMeter: Sendable {
    var frames = 0
    var level: Float = 0
    var lastBufferAt = Date()
    var error: String?
}

/// The tap copies audio into a bounded disk-write queue. Queue overflow is an error,
/// never a silent dropped buffer. Audio is raw mono Float32 LE, with sample rate
/// persisted BEFORE the engine starts, so it remains recoverable without a CAF header.
private final class AudioSink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "LocalDictation.AudioDisk", qos: .userInitiated)
    private let capacity = DispatchSemaphore(value: 16)
    private let lock = NSLock()
    private let handle: FileHandle
    private var meter = RecordingMeter()
    private var lastSync = Date()
    private var finished = false // accessed only on disk queue

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw DictationError.message("Cannot create a recovery recording. Check disk space and folder permissions.")
        }
        handle = try FileHandle(forWritingTo: url)
    }
    func snapshot() -> RecordingMeter { lock.lock(); defer { lock.unlock() }; return meter }
    func fail(_ message: String) { lock.lock(); defer { lock.unlock() }; if meter.error == nil { meter.error = message } }
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard snapshot().error == nil else { return }
        guard buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved,
              let channels = buffer.floatChannelData, buffer.format.channelCount > 0 else {
            fail("The microphone supplied an unsupported audio format. Saved audio was retained."); return
        }
        guard capacity.wait(timeout: .now()) == .success else {
            fail("The recording disk could not keep up. Recording was stopped rather than silently dropping audio."); return
        }
        let count = Int(buffer.frameLength)
        var mono = [Float](repeating: 0, count: count)
        let channelCount = Int(buffer.format.channelCount)
        var squareSum: Float = 0
        for i in 0..<count {
            var sample: Float = 0
            for channel in 0..<channelCount { sample += channels[channel][i] }
            sample /= Float(channelCount)
            mono[i] = sample.isFinite ? sample : 0
            squareSum += mono[i] * mono[i]
        }
        // Supported Macs are little endian. Use a single copy, not one Data append per sample.
        let data = mono.withUnsafeBytes { Data($0) }
        let rms = sqrt(squareSum / Float(max(1, count)))
        queue.async { [self] in
            defer { capacity.signal() }
            guard !finished else { return }
            do {
                try handle.write(contentsOf: data)
                if Date().timeIntervalSince(lastSync) >= 1 {
                    try handle.synchronize(); lastSync = Date()
                }
                lock.lock()
                meter.frames += count
                meter.level = min(1, max(0, (20 * log10(max(rms, 0.000_001)) + 60) / 60))
                meter.lastBufferAt = Date()
                lock.unlock()
            } catch { fail("Audio could not be saved: \(error.localizedDescription)") }
        }
    }
    func finish() async -> RecordingMeter {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if !finished {
                    finished = true
                    do { try handle.synchronize(); try handle.close() }
                    catch { fail("Could not finalise the recording: \(error.localizedDescription)") }
                }
                continuation.resume(returning: snapshot())
            }
        }
    }
}

@MainActor
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var sink: AudioSink?
    private var configurationObserver: NSObjectProtocol?
    private(set) var sampleRate: Double = 0
    static var microphoneGranted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
    func prepare() throws -> Double {
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw DictationError.message("No usable microphone is available. Select an input device in System Settings.")
        }
        self.engine = engine; self.sampleRate = format.sampleRate
        return format.sampleRate
    }
    func start(at url: URL) throws {
        guard let engine else { throw DictationError.message("Audio capture was not prepared.") }
        let sink = try AudioSink(url: url)
        self.sink = sink
        let format = engine.inputNode.outputFormat(forBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            sink.enqueue(buffer)
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in sink.fail("The microphone configuration changed. Saved audio was retained; start a new recording.") }
        do { engine.prepare(); try engine.start() }
        catch { engine.inputNode.removeTap(onBus: 0); engine.stop(); throw error }
    }
    var snapshot: RecordingMeter { sink?.snapshot() ?? RecordingMeter() }
    func stop() async -> RecordingMeter {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.stop()
        if sink != nil { engine?.inputNode.removeTap(onBus: 0) }
        let result = await sink?.finish() ?? RecordingMeter()
        sink = nil; engine = nil
        return result
    }
}
