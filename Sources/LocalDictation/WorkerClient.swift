import Foundation
import Darwin
import DictationCore

@MainActor
final class WorkerClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var outputBuffer = Data()
    private var generation = UUID()
    private var pending: (UUID, CheckedContinuation<WorkerResponse, Error>)?
    var onExit: (() -> Void)?

    func request(_ request: WorkerRequest) async throws -> WorkerResponse {
        guard pending == nil else { throw DictationError.message("The recogniser is already processing a request.") }
        try launchIfNeeded()
        let payload = try JSONEncoder().encode(request) + Data([0x0A])
        return try await withCheckedThrowingContinuation { continuation in
            pending = (request.id, continuation)
            do { try input?.write(contentsOf: payload) }
            catch { failPending(error); stop() }
        }
    }
    func stop() {
        generation = UUID()
        output?.readabilityHandler = nil
        try? output?.close(); output = nil
        outputBuffer.removeAll()
        try? input?.close(); input = nil
        let oldProcess = process
        process = nil
        if let oldProcess, oldProcess.isRunning {
            oldProcess.terminate()
            // A stuck GPU call must not keep the UI waiting forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if oldProcess.isRunning { kill(oldProcess.processIdentifier, SIGKILL) }
            }
        }
        failPending(CancellationError())
        onExit?()
    }
    private func launchIfNeeded() throws {
        if process?.isRunning == true { return }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/DictationWorker")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw DictationError.message("The transcription helper is missing. Run the packaged .app built by Scripts/build-app.sh, not swift run.")
        }
        let child = Process()
        let stdin = Pipe(); let stdout = Pipe()
        child.executableURL = helper
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = "1"; environment["TRANSFORMERS_OFFLINE"] = "1"
        environment.removeValue(forKey: "HF_TOKEN")
        child.environment = environment
        child.currentDirectoryURL = Bundle.main.resourceURL
        let token = UUID(); generation = token
        child.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.process = nil
                self.failPending(DictationError.message("The recogniser exited (status \(status)). Your saved recording is available for retry."))
                self.onExit?()
            }
        }
        try child.run()
        process = child; input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        outputBuffer.removeAll()
        // AsyncBytes pipe readers can block each other while the idle speech
        // worker waits for input. Read each ready pipe independently instead.
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.receive(data)
            }
        }
    }
    private func receive(_ data: Data) {
        outputBuffer.append(data)
        do {
            while let newline = outputBuffer.firstIndex(of: 0x0A) {
                let line = String(decoding: outputBuffer[..<newline], as: UTF8.self)
                outputBuffer.removeSubrange(...newline)
                guard line.hasPrefix(WorkerResponse.prefix) else { continue }
                let payload = Data(line.dropFirst(WorkerResponse.prefix.count).utf8)
                let response = try JSONDecoder().decode(WorkerResponse.self, from: payload)
                guard let pending, pending.0 == response.id else { continue }
                self.pending = nil
                if response.success { pending.1.resume(returning: response) }
                else { pending.1.resume(throwing: DictationError.message(response.message ?? "Transcription failed.")) }
            }
        } catch {
            failPending(error)
            stop()
        }
    }
    private func failPending(_ error: Error) {
        guard let pending else { return }
        self.pending = nil
        pending.1.resume(throwing: error)
    }
}
