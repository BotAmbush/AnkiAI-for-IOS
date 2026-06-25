import Foundation

/// Persisted snapshot of an unfinished AI creator session (Issue 3). Stored as a
/// JSON file in Application Support (NOT UserDefaults) so it survives sheet
/// dismissal, tab switches, backgrounding and relaunch. Attachments are kept as
/// their base64 payloads in the same app-controlled file.
public struct PersistedCreatorSession: Codable, Equatable {
    public var draft: String = ""
    public var language: String = AILanguage.automatic.rawValue
    public var addedCount: Int = 0
    public var parseFailed: Bool = false
    public var rawResponse: String?
    public var lastPrompt: String?
    public var proposals: [PersistedProposal] = []
    public var attachments: [PersistedAttachment] = []
}

public struct PersistedProposal: Codable, Equatable {
    public var front: String
    public var back: String
    public var deckName: String
    public var deckId: Int64
}

public struct PersistedAttachment: Codable, Equatable {
    public var base64: String
    public var mediaType: String
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
    }
}
