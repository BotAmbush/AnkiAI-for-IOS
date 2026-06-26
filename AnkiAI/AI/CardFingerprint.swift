import Foundation

/// Stable normalized fingerprint of a card for per-session duplicate detection
/// (Repair 3). Normalization strips HTML tags and collapses whitespace so harmless
/// formatting differences do NOT count as different cards, while genuinely different
/// content does.
public enum CardFingerprint {

    /// Strip HTML tags, decode a few common entities, collapse whitespace, lowercase.
    public static func normalize(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (e, r) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"] {
            t = t.replacingOccurrences(of: e, with: r)
        }
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func make(notetypeId: Int64, deckId: Int64, fields: [String], tags: [String] = []) -> String {
        let f = fields.map(normalize).joined(separator: "\u{1f}")
        let t = tags.map { $0.lowercased() }.sorted().joined(separator: ",")
        return "\(notetypeId)|\(deckId)|\(f)|\(t)"
    }
}
