import Foundation

/// Single message in a Claude chat session. Mirrors `ai/chat/AiChatMessage.kt`
/// (Room entity `ai_chat_messages`). Stored in the separate AI database, never
/// in Anki's collection.
public struct AIChatMessage: Equatable, Identifiable, Sendable {
    public var id: Int64
    public let sessionId: String
    /// "user" | "assistant"
    public let role: String
    public let content: String
    /// "text" | "edit_proposal" | "add_card_proposal"
    public let messageType: String
    /// JSON payload for proposals; empty for regular messages.
    public let metadata: String
    public let timestamp: Int64

    public init(id: Int64 = 0, sessionId: String, role: String, content: String,
                messageType: String = AIChatMessage.typeText, metadata: String = "",
                timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.messageType = messageType
        self.metadata = metadata
        self.timestamp = timestamp
    }

    public static let typeText = "text"
    public static let typeEditProposal = "edit_proposal"
    public static let typeAddCardProposal = "add_card_proposal"
    public static let roleUser = "user"
    public static let roleAssistant = "assistant"
}
