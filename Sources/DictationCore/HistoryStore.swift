import Foundation

public struct HistorySnapshot: Sendable {
    public var sessions: [DictationSession]
    public var warnings: [String]
}

/// One directory per recording avoids a single corrupt database losing the whole history.
/// Updates are atomic and serialised. Audio is deliberately separate from transcript metadata.
public actor HistoryStore {
    public let root: URL
    private let fm = FileManager.default
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }
    public nonisolated func directory(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }
    public nonisolated func audioURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("audio.f32le")
    }
    private func metadataURL(_ id: UUID) -> URL {
        directory(for: id).appendingPathComponent("session.json")
    }
    public func create(_ session: DictationSession) throws {
        guard !fm.fileExists(atPath: directory(for: session.id).path) else {
            throw DictationError.message("A session with this identifier already exists.")
        }
        guard session.sampleRate.isFinite, session.sampleRate >= 8_000, session.sampleRate <= 384_000 else {
            throw DictationError.message("The microphone reported an invalid sample rate.")
        }
        try fm.createDirectory(at: directory(for: session.id), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try persist(session)
    }
    public func read(_ id: UUID) throws -> DictationSession {
        let session = try JSONDecoder().decode(DictationSession.self, from: Data(contentsOf: metadataURL(id)))
        guard session.schema == DictationSession.schemaVersion, session.id == id else {
            throw DictationError.message("Unsupported or mismatched session metadata: \(id).")
        }
        return session
    }
    @discardableResult
    public func update(_ id: UUID, _ mutation: @Sendable (inout DictationSession) -> Void) throws -> DictationSession {
        var session = try read(id)
        mutation(&session)
        session.updatedAt = Date()
        try persist(session)
        return session
    }
    private func persist(_ session: DictationSession) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(session).write(to: metadataURL(session.id), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataURL(session.id).path)
    }
    public func snapshot(recoverInterrupted: Bool = false) throws -> HistorySnapshot {
        var sessions: [DictationSession] = []
        var warnings: [String] = []
        let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        for child in children {
            guard let id = UUID(uuidString: child.lastPathComponent) else { continue }
            do {
                var session = try read(id)
                if recoverInterrupted && [.recording, .transcribing].contains(session.state) {
                    if let size = try? fm.attributesOfItem(atPath: audioURL(for: id).path)[.size] as? NSNumber {
                        session.frameCount = size.intValue / MemoryLayout<Float>.size
                    }
                    session.state = session.attempts.isEmpty ? .interrupted : .needsReview
                    session.note = "An earlier operation was interrupted. Saved audio and earlier transcripts were retained."
                    session.updatedAt = Date()
                    try persist(session)
                }
                sessions.append(session)
            } catch {
                // Leave unreadable entries untouched, and surface the issue rather than
                // presenting a corrupt history as an empty history.
                warnings.append("Could not read \(child.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return HistorySnapshot(sessions: sessions.sorted { $0.createdAt > $1.createdAt }, warnings: warnings)
    }
    public func appendAttempt(_ attempt: TranscriptAttempt, to id: UUID) throws {
        _ = try update(id) { session in
            session.attempts.append(attempt)
            session.editedText = nil
            session.state = attempt.warnings.isEmpty && !attempt.text.isEmpty ? .ready : .needsReview
            session.delivery = .pending
            session.note = attempt.warnings.isEmpty ? nil : attempt.warnings.joined(separator: "\n")
        }
    }
    public func prune(_ policy: RecoveryPolicy, protecting: Set<UUID> = [], now: Date = Date()) throws {
        try policy.validate()
        let current = try snapshot()
        for id in policy.expired(in: current.sessions, protecting: protecting, now: now) {
            try delete(id)
        }
    }

    public func deleteAudio(_ id: UUID) throws {
        var session = try read(id)
        guard ![.recording, .transcribing].contains(session.state) else {
            throw DictationError.message("An active recording cannot be deleted.")
        }
        let audio = audioURL(for: id)
        if fm.fileExists(atPath: audio.path) { try fm.removeItem(at: audio) }
        session.audioDeleted = true
        session.updatedAt = Date()
        try persist(session)
    }
    public func delete(_ id: UUID) throws {
        let session = try read(id)
        guard ![.recording, .transcribing].contains(session.state) else {
            throw DictationError.message("An active recording cannot be deleted.")
        }
        try fm.removeItem(at: directory(for: id))
    }
}

public enum SettingsFile {
    public static func load(from url: URL) throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppSettings() }
        let value = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))
        guard value.schema == 1 else { throw DictationError.message("Unsupported settings version.") }
        try value.validate()
        return value
    }
    public static func save(_ settings: AppSettings, to url: URL) throws {
        try settings.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
