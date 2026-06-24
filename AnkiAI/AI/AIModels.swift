import Foundation

/// Context about the card under review, gathered for the AI chat.
/// Mirrors `CardChatContext` in `ai/chat/AiChatViewModel.kt`.
public struct CardChatContext: Equatable, Sendable {
    public let cardId: Int64
    public let noteId: Int64
    public let front: String
    public let back: String
    public let frontRaw: String
    public let backRaw: String
    public let deckName: String
    public let deckHierarchy: String
    public let fieldNames: [String]

    public init(cardId: Int64, noteId: Int64, front: String, back: String,
                frontRaw: String, backRaw: String, deckName: String,
                deckHierarchy: String, fieldNames: [String]) {
        self.cardId = cardId
        self.noteId = noteId
        self.front = front
        self.back = back
        self.frontRaw = frontRaw
        self.backRaw = backRaw
        self.deckName = deckName
        self.deckHierarchy = deckHierarchy
        self.fieldNames = fieldNames
    }
}

/// A proposed edit to an existing note field. Mirrors `EditProposal`.
public struct EditProposal: Equatable, Sendable {
    public let noteId: Int64
    public let fieldIndex: Int
    public let fieldName: String
    public let oldContent: String
    public let newContent: String
    public let explanation: String
}

/// A proposed new card from the reviewer chat. Mirrors `AddCardProposal`.
public struct AddCardProposal: Equatable, Sendable {
    public let front: String
    public let back: String
    public let deckId: Int64
    public let deckName: String
    public let explanation: String
}

/// A generated card from the creator flow. Mirrors `CardProposal`.
public struct CardProposal: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public let front: String
    public let back: String
    public let deckName: String
    public let deckId: Int64

    public init(front: String, back: String, deckName: String, deckId: Int64) {
        self.front = front
        self.back = back
        self.deckName = deckName
        self.deckId = deckId
    }
}

/// Outcome of interpreting an assistant reply: either plain text, or a structured action.
public enum AssistantReply: Equatable {
    case text(String)
    case editCard(fieldName: String, newContent: String, explanation: String)
    case addCard(front: String, back: String, deckName: String, explanation: String)
}

/// Pure parsing/interpretation helpers extracted from `AiChatViewModel` so they
/// are unit-testable without a collection or network.
public enum AIResponseParser {

    /// Port of `extractJsonBlock` — find a single JSON object in the reply.
    public static func extractJSONObject(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") { return trimmed }
        return fencedBlock(in: text)
    }

    /// Port of `extractJsonArray` — find a JSON array in the reply.
    public static func extractJSONArray(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { return trimmed }
        if let block = fencedBlock(in: text) { return block }
        if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end {
            return String(text[start...end])
        }
        return nil
    }

    /// Matches ```json ... ``` or ``` ... ``` fenced blocks (DOTALL).
    private static func fencedBlock(in text: String) -> String? {
        let pattern = "```(?:json)?\\s*\\n?(.+?)\\n?```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Interpret a reviewer-chat assistant reply (port of `handleAssistantReply`).
    public static func interpretReviewerReply(_ reply: String) -> AssistantReply {
        guard let block = extractJSONObject(reply),
              let data = block.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .text(reply)
        }
        switch json["action"] as? String {
        case "edit_card":
            guard let fieldName = json["fieldName"] as? String,
                  let newContent = json["newContent"] as? String else { return .text(reply) }
            return .editCard(fieldName: fieldName, newContent: newContent,
                             explanation: json["explanation"] as? String ?? "")
        case "add_card":
            guard let deckName = json["deckName"] as? String,
                  let front = json["front"] as? String,
                  let back = json["back"] as? String else { return .text(reply) }
            return .addCard(front: front, back: back, deckName: deckName,
                            explanation: json["explanation"] as? String ?? "")
        default:
            return .text(reply)
        }
    }

    /// Parsed creator card before deck resolution. Mirrors the per-item parse in
    /// `parseGenerationProposals` (front_html|front, back_html|back, deckName).
    public struct RawGeneratedCard: Equatable {
        public let front: String
        public let back: String
        public let deckName: String
    }

    /// Parse the creator JSON array into raw cards (deck resolution happens later
    /// against the live collection).
    public static func parseGeneratedCards(_ reply: String) -> [RawGeneratedCard]? {
        guard let jsonText = extractJSONArray(reply),
              let data = jsonText.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return arr.map { obj in
            let front = nonEmpty(obj["front_html"]) ?? (obj["front"] as? String ?? "")
            let back = nonEmpty(obj["back_html"]) ?? (obj["back"] as? String ?? "")
            let deck = nonEmpty(obj["deckName"]) ?? "Default"
            return RawGeneratedCard(front: front, back: back, deckName: deck)
        }
    }

    private static func nonEmpty(_ any: Any?) -> String? {
        guard let s = any as? String, !s.isEmpty else { return nil }
        return s
    }
}
