import Foundation

public enum CaptureState: String, Codable, Sendable, CaseIterable {
    case recording, captured, transcribing, ready, needsReview, failed, interrupted
    public var label: String {
        switch self {
        case .recording: return "Recording"
        case .captured: return "Audio saved"
        case .transcribing: return "Transcribing"
        case .ready: return "Ready"
        case .needsReview: return "Review needed"
        case .failed: return "Retry needed"
        case .interrupted: return "Recovered recording"
        }
    }
}

public enum DeliveryState: String, Codable, Sendable {
    case pending, insertionRequested, inserted, pasteRequested, copied, dismissed
    public var label: String {
        switch self {
        case .pending: return "Pending"
        case .insertionRequested: return "Insertion requested — check destination"
        case .inserted: return "Inserted via Accessibility"
        case .pasteRequested: return "Paste requested (not verified)"
        case .copied: return "Copied"
        case .dismissed: return "Archived"
        }
    }
}

public struct VocabularyProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var terms: String
    public init(id: UUID = UUID(), name: String, terms: String) {
        self.id = id; self.name = name; self.terms = terms
    }
}

public struct TranscriptAttempt: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var text: String
    public var model: String
    public var vocabulary: String
    public var language: String
    public var processingSeconds: Double
    public var audioSeconds: Double
    public var generationTokens: Int
    public var warnings: [String]
    public init(id: UUID = UUID(), createdAt: Date = Date(), text: String, model: String,
                vocabulary: String, language: String = "English", processingSeconds: Double,
                audioSeconds: Double, generationTokens: Int, warnings: [String] = []) {
        self.id = id; self.createdAt = createdAt; self.text = text; self.model = model
        self.vocabulary = vocabulary; self.language = language
        self.processingSeconds = processingSeconds; self.audioSeconds = audioSeconds
        self.generationTokens = generationTokens; self.warnings = warnings
    }
}

public struct DictationSession: Codable, Identifiable, Equatable, Sendable {
    public static let schemaVersion = 1
    public var schema: Int = schemaVersion
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var state: CaptureState = .recording
    public var delivery: DeliveryState = .pending
    public var sampleRate: Double
    public var language: String = "English"
    public var frameCount: Int = 0
    public var profileName: String
    public var vocabulary: String
    public var targetApplication: String?
    public var attempts: [TranscriptAttempt] = []
    public var editedText: String?
    public var note: String?
    public var audioDeleted: Bool = false
    public var duration: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }
    public var text: String { editedText ?? attempts.last?.text ?? "" }
    public var canInsert: Bool {
        (state == .ready || state == .needsReview) && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public init(id: UUID = UUID(), date: Date = Date(), sampleRate: Double,
                profileName: String, vocabulary: String, targetApplication: String? = nil) {
        self.id = id; self.createdAt = date; self.updatedAt = date
        self.sampleRate = sampleRate; self.profileName = profileName
        self.vocabulary = vocabulary; self.targetApplication = targetApplication
    }
}

public struct HotKeyBinding: Codable, Equatable, Sendable {
    // Carbon key codes/modifier masks are stored as plain integers to keep Core portable.
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var display: String
    public init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.display = display
    }
    public static let record = Self(keyCode: 49, modifiers: 6144, display: "⌃⌥Space")
    public static let insert = Self(keyCode: 9, modifiers: 6144, display: "⌃⌥V")
    public static let history = Self(keyCode: 4, modifiers: 6144, display: "⌃⌥H")
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var schema: Int = 1
    public var globalTerms = ""
    public var profiles: [VocabularyProfile] = []
    // Optional fields preserve decoding of settings saved by the original app.
    public var recoveryPolicy: RecoveryPolicy?
    public var effectiveRecoveryPolicy: RecoveryPolicy { recoveryPolicy ?? RecoveryPolicy() }
    public var repositoriesPath: String?
    public var repositoryVocabulary: RepositoryVocabulary?
    public var selectedProfileID: UUID?
    public var modelDirectory: String = ""
    public var automaticInsertion = true
    public var allowPasteFallback = true
    public var allowTerminalApps = false
    public var recordShortcut = HotKeyBinding.record
    public var insertShortcut = HotKeyBinding.insert
    public var historyShortcut = HotKeyBinding.history
    public var tokenBudgetMultiplier: Int = 1
    public var language = "English"
    public init() {}
    public var effectiveRepositoriesPath: String { repositoriesPath ?? "~/repos" }
    public var selectedProfile: VocabularyProfile? { profiles.first { $0.id == selectedProfileID } }
    public var vocabularyContext: String {
        Vocabulary.terms((repositoryVocabulary?.names ?? []) .joined(separator: "\n") + "\n" +
            globalTerms + "\n" + profiles.map { $0.name + "\n" + $0.terms }.joined(separator: "\n") + "\n" +
            CodingVocabulary.terms(for: repositoryVocabulary?.projectTypes ?? []).joined(separator: "\n"))
            .joined(separator: ", ")
    }
    public func validate() throws {
        try effectiveRecoveryPolicy.validate()
        let bindings = [recordShortcut, insertShortcut, historyShortcut]
        guard Set(bindings.map { "\($0.keyCode):\($0.modifiers)" }).count == 3 else {
            throw DictationError.message("The three shortcuts must be different.")
        }
        // Require a non-Shift modifier so ordinary typing cannot start a recording.
        guard bindings.allSatisfy({ ($0.modifiers & 6400) != 0 }) else {
            throw DictationError.message("Shortcuts need Control, Option or Command.")
        }
        guard (1...4).contains(tokenBudgetMultiplier) else {
            throw DictationError.message("Token budget multiplier must be between 1 and 4.")
        }
        try Vocabulary.validate(vocabularyContext)
    }
}

public enum DictationError: Error, LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
