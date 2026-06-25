import Foundation

/// User-selectable output language for the AI reviewer + creator (Issue 2).
public enum AILanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case hebrew
    case english

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .hebrew: return "Hebrew"
        case .english: return "English"
        }
    }

    /// Explicit instruction injected into the Claude prompt. Must NOT change the
    /// JSON/schema the model returns — only the natural-language content.
    public var promptInstruction: String {
        switch self {
        case .automatic:
            return "Respond in the dominant language of the card / source text / user prompt. " +
                   "If that language is Hebrew, write all natural-language content in Hebrew (keep formulas, code and Latin technical terms LTR)."
        case .hebrew:
            return "Write ALL natural-language content (explanations and card fields) in Hebrew. " +
                   "Keep mathematical formulas, code, numbers and Latin technical terms in their natural LTR form. " +
                   "Do NOT change the JSON keys or structure — only the human-readable values."
        case .english:
            return "Write all natural-language content in English."
        }
    }
}

/// First-strong bidi direction detection (no string reversal — semantic direction).
public enum TextDirection {

    /// True if the first strongly-directional character is RTL (Hebrew/Arabic).
    /// Neutral characters (digits, punctuation, Latin-less symbols) are skipped.
    public static func firstStrongIsRTL(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            // Strong RTL: Hebrew (0590–05FF), Arabic (0600–06FF, 0750–077F), etc.
            if (0x0590...0x05FF).contains(v) || (0x0600...0x06FF).contains(v) ||
               (0x0750...0x077F).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v) {
                return true
            }
            // Strong LTR: basic Latin letters + Latin-1/Extended letters.
            if (0x0041...0x005A).contains(v) || (0x0061...0x007A).contains(v) ||
               (0x00C0...0x024F).contains(v) {
                return false
            }
        }
        return false
    }

    /// Whether the UI should present `text` right-to-left for the chosen language.
    public static func isRTL(language: AILanguage, text: String) -> Bool {
        switch language {
        case .hebrew: return true
        case .english: return false
        case .automatic: return firstStrongIsRTL(text)
        }
    }
}
