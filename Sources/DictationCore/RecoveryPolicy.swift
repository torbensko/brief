import Foundation

public struct RecoveryPolicy: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case count, minutes }
    public var mode: Mode
    public var value: Int
    public init(mode: Mode = .count, value: Int = 1) { self.mode = mode; self.value = value }
    public func validate() throws {
        guard (1...100).contains(value) else { throw DictationError.message("Keep between 1 and 100 recent entries or minutes.") }
    }
    public func expired(in sessions: [DictationSession], protecting: Set<UUID> = [], now: Date = Date()) -> [UUID] {
        let settled = sessions.filter { ![.recording, .transcribing].contains($0.state) }
            .sorted { $0.createdAt > $1.createdAt }
        let candidates: [DictationSession]
        switch mode {
        case .count:
            // Overlapping recordings are one recovery unit, just as they are one
            // clipboard unit. Never discard earlier pieces of the latest dictation.
            var retainedGroups = Set<UUID>()
            candidates = settled.filter { session in
                let group = session.clipboardGroupID ?? session.id
                if retainedGroups.contains(group) { return false }
                if retainedGroups.count < max(1, value) { retainedGroups.insert(group); return false }
                return true
            }
        case .minutes:
            candidates = settled.filter {
                let availableAt = $0.cleanup?.createdAt ?? $0.attempts.last?.createdAt ?? $0.updatedAt
                return now.timeIntervalSince(availableAt) >= Double(max(1, value)) * 60
            }
        }
        return candidates.filter { !protecting.contains($0.id) }.map(\.id)
    }
}
