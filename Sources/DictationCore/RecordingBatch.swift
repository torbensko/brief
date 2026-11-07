import Foundation

/// A new capture joins the current batch while any member is still alive, including
/// microphone preparation, queued work and cleanup. Results always retain capture order.
public struct RecordingBatch: Sendable {
    public enum Stage: String, Sendable {
        case preparing, recording, saving, queued, transcribing, cleaning, complete, failed
        public var isActive: Bool { self != .complete && self != .failed }
    }
    public struct Item: Identifiable, Sendable {
        public let id: UUID
        public var stage: Stage
        public var message: String
        public var clipboardText = ""
        public var originalChosen = false
    }
    public private(set) var id = UUID()
    public private(set) var items: [Item] = []
    public var isActive: Bool { items.contains { $0.stage.isActive } }
    public var isGrouped: Bool { items.count > 1 }
    public var clipboardText: String {
        items.map(\.clipboardText).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
    public init() {}
    @discardableResult public mutating func begin(_ sessionID: UUID, stage: Stage = .preparing) -> UUID {
        if !isActive { id = UUID(); items = [] }
        guard !items.contains(where: { $0.id == sessionID }) else { return id }
        items.append(Item(id: sessionID, stage: stage, message: "Preparing microphone…"))
        return id
    }
    public mutating func update(_ sessionID: UUID, stage: Stage? = nil, message: String? = nil) {
        guard let index = items.firstIndex(where: { $0.id == sessionID }) else { return }
        if let stage { items[index].stage = stage }
        if let message { items[index].message = message }
    }
    public mutating func removeExpired(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) && !$0.stage.isActive }
    }
    /// Returns whether the assembled clipboard changed. Explicitly taking the original
    /// pins only that member; later recordings can still append their results.
    @discardableResult public mutating func publish(_ text: String, for sessionID: UUID, chooseOriginal: Bool = false) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == sessionID }),
              !items[index].originalChosen || chooseOriginal else { return false }
        let before = clipboardText
        items[index].clipboardText = text
        if chooseOriginal { items[index].originalChosen = true }
        return clipboardText != before
    }
}
