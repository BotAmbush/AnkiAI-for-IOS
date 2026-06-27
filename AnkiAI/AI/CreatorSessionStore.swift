import Foundation

/// Persisted snapshot of an unfinished AI creator session (Issue 3). Stored as a
/// JSON file in Application Support (NOT UserDefaults) so it survives sheet
/// dismissal, tab switches, backgrounding and relaunch. Attachments are stored as
/// metadata-only references (`CreatorAttachmentRef`); the bytes live in scoped files
/// under CreatorSessions/<id>/Attachments/ — never inline in this JSON.
public struct PersistedCreatorSession: Codable, Equatable {
    public var draft: String = ""
    public var language: String = AILanguage.automatic.rawValue
    public var addedCount: Int = 0
    public var parseFailed: Bool = false
    public var repairAttempted: Bool = false      // Repair 2: persist retry state
    public var rawResponse: String?
    public var lastPrompt: String?
    public var selectedDeckId: Int64?             // Repair 1: persisted creator deck
    public var selectedDeckPath: String?
    public var proposals: [PersistedProposal] = []
    /// Metadata ONLY — the attachment bytes live in scoped files (Repair 2).
    public var attachments: [CreatorAttachmentRef] = []
    /// Accepted-card fingerprints to suppress duplicates (Repair 3).
    public var acceptedFingerprints: [String] = []
}

public struct PersistedProposal: Codable, Equatable {
    public var front: String
    public var back: String
    public var deckName: String
    public var deckId: Int64
}

public enum CreatorSessionStore {
    private static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("AICreatorSessions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(_ sessionId: String) throws -> URL {
        let safe = sessionId.replacingOccurrences(of: "/", with: "_")
        return try directory().appendingPathComponent("\(safe).json")
    }

    public static func save(_ session: PersistedCreatorSession, sessionId: String) {
        guard let url = try? fileURL(sessionId),
              let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func load(sessionId: String) -> PersistedCreatorSession? {
        guard let url = try? fileURL(sessionId),
              let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(PersistedCreatorSession.self, from: data) else { return nil }
        return session
    }

    public static func clear(sessionId: String) {
        if let url = try? fileURL(sessionId) { try? FileManager.default.removeItem(at: url) }
        CreatorAttachmentStore.clear(sessionId: sessionId)   // remove scoped attachment files too
    }
}
