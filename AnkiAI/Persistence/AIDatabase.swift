import Foundation

/// The separate AI database (`ai_insights.db`). Mirrors `ai/data/AiDatabase.kt`.
///
/// IMPORTANT: This is a SEPARATE database file from Anki's `collection.anki2`.
/// It only ever holds `ai_*` tables (chat messages, card meta, study log) and is
/// never opened by the collection/Rust-backend code.
public final class AIDatabase {
    private let db: SQLiteDatabase

    /// Open at the given file path (or ":memory:" for tests).
    public init(path: String) throws {
        self.db = try SQLiteDatabase(path: path)
        try migrate()
    }

    /// Convenience: open `ai_insights.db` in the app's Application Support dir.
    public static func makeDefault() throws -> AIDatabase {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let url = dir.appendingPathComponent("ai_insights.db")
        return try AIDatabase(path: url.path)
    }

    private func migrate() throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS ai_chat_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sessionId TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            messageType TEXT NOT NULL DEFAULT 'text',
            metadata TEXT NOT NULL DEFAULT '',
            timestamp INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_chat_session ON ai_chat_messages(sessionId, timestamp);
        """)
    }

    // MARK: - Chat DAO (port of AiChatDao)

    @discardableResult
    public func insert(_ message: AIChatMessage) throws -> Int64 {
        try db.run(
            "INSERT INTO ai_chat_messages (sessionId, role, content, messageType, metadata, timestamp) VALUES (?, ?, ?, ?, ?, ?)",
            [.text(message.sessionId), .text(message.role), .text(message.content),
             .text(message.messageType), .text(message.metadata), .int(message.timestamp)]
        )
    }

    public func messages(sessionId: String) throws -> [AIChatMessage] {
        try db.query(
            "SELECT id, sessionId, role, content, messageType, metadata, timestamp FROM ai_chat_messages WHERE sessionId = ? ORDER BY timestamp ASC",
            [.text(sessionId)]
        ) { row in
            AIChatMessage(
                id: row.int(0), sessionId: row.string(1), role: row.string(2),
                content: row.string(3), messageType: row.string(4), metadata: row.string(5),
                timestamp: row.int(6)
            )
        }
    }

    public func deleteSession(_ sessionId: String) throws {
        try db.run("DELETE FROM ai_chat_messages WHERE sessionId = ?", [.text(sessionId)])
    }
}
