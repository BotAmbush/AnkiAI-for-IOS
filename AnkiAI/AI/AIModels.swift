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

/// A proposed new card from the reviewer chat. `deckName` is NON-authoritative
/// proposal metadata — the deck is resolved only at approval time, never created or
/// defaulted before the user approves.
public struct AddCardProposal: Equatable, Sendable {
    public let front: String
    public let back: String
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

    /// Result of parsing a creator response: the valid cards, a list of human-readable
    /// reasons for any skipped/invalid cards, and the recovery stage that matched
    /// (sanitized diagnostics — never the card content itself).
    public struct CardParseOutcome: Equatable {
        public let cards: [RawGeneratedCard]
        public let skipped: [String]
        public let stage: String
        public init(cards: [RawGeneratedCard], skipped: [String], stage: String) {
            self.cards = cards; self.skipped = skipped; self.stage = stage
        }
    }

    /// Robust local recovery from the common valid model variations: a top-level
    /// array, a `{ "cards": [...] }` envelope, a single card object, JSON inside
    /// Markdown fences, prose before/after the JSON, a leading BOM, and one malformed
    /// card among otherwise valid ones (skipped + reported, valid ones preserved).
    /// Returns `nil` only when NO card can be safely recovered.
    public static func parseGeneratedCards(_ reply: String) -> CardParseOutcome? {
        var text = reply
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }          // strip BOM
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Candidate JSON strings in priority order (stage label = diagnostics).
        var candidates: [(String, String)] = []
        if let fenced = fencedBlock(in: text) { candidates.append((fenced, "fenced")) }
        candidates.append((text, "whole"))
        if let s = text.firstIndex(of: "["), let e = text.lastIndex(of: "]"), s < e {
            candidates.append((String(text[s...e]), "array-slice"))
        }
        if let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}"), s < e {
            candidates.append((String(text[s...e]), "object-slice"))
        }
        for (candidate, stage) in candidates {
            if let outcome = cardsFromJSONString(candidate, stage: stage) { return outcome }
        }
        return nil
    }

    private static func cardsFromJSONString(_ s: String, stage: String) -> CardParseOutcome? {
        guard let data = s.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        var elements: [Any]?
        if let a = any as? [Any] {
            elements = a
        } else if let obj = any as? [String: Any] {
            if let c = obj["cards"] as? [Any] { elements = c }
            else if obj["front"] != nil || obj["front_html"] != nil { elements = [obj] }  // single card
        }
        guard let items = elements else { return nil }

        var cards: [RawGeneratedCard] = []
        var skipped: [String] = []
        for (i, el) in items.enumerated() {
            guard let obj = el as? [String: Any] else {
                skipped.append("Card \(i + 1): not a JSON object"); continue
            }
            let front = nonEmpty(obj["front_html"]) ?? (obj["front"] as? String ?? "")
            let back = nonEmpty(obj["back_html"]) ?? (obj["back"] as? String ?? "")
            let deck = nonEmpty(obj["deckName"]) ?? nonEmpty(obj["deck"]) ?? "Default"
            guard !front.isEmpty else { skipped.append("Card \(i + 1): missing front/front_html"); continue }
            cards.append(RawGeneratedCard(front: front, back: back, deckName: deck))
        }
        guard !cards.isEmpty else { return nil }
        return CardParseOutcome(cards: cards, skipped: skipped, stage: stage)
    }

    private static func nonEmpty(_ any: Any?) -> String? {
        guard let s = any as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : s
    }
}
