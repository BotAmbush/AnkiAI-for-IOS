import Foundation

/// Text/HTML helpers ported from `AiChatViewModel` (`stripHtml`, `mathAwareStripHtml`).
/// Used to build plain-text card context for prompts while preserving math markers.
public enum HTMLText {

    /// Port of `String.stripHtml()`.
    public static func stripHTML(_ input: String) -> String {
        var s = replaceRegex(input, "<[^>]+>", with: " ")
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = replaceRegex(s, "\\s+", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Port of `String.mathAwareStripHtml()` — converts `\[ \]`, `\( \)` and
    /// `<anki-mathjax>` into `[math: ...]` markers before stripping tags, so the
    /// model still sees the formula content as plain text.
    public static func mathAwareStripHTML(_ input: String) -> String {
        var s = input
        s = replaceRegexCapture(s, "\\\\\\[(.+?)\\\\\\]") { "[math: \($0.trimmingCharacters(in: .whitespacesAndNewlines))]" }
        s = replaceRegexCapture(s, "\\\\\\((.+?)\\\\\\)") { "[math: \($0.trimmingCharacters(in: .whitespacesAndNewlines))]" }
        s = replaceRegexCapture(s, "<anki-mathjax[^>]*>([^<]+)</anki-mathjax>", caseInsensitive: true) {
            "[math: \($0.trimmingCharacters(in: .whitespacesAndNewlines))]"
        }
        s = replaceRegex(s, "<[^>]+>", with: " ")
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = replaceRegex(s, "\\s+", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Regex helpers

    private static func replaceRegex(_ input: String, _ pattern: String, with template: String,
                                     caseInsensitive: Bool = false) -> String {
        let opts: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive, .dotMatchesLineSeparators] : [.dotMatchesLineSeparators]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: opts) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: template)
    }

    private static func replaceRegexCapture(_ input: String, _ pattern: String,
                                            caseInsensitive: Bool = false,
                                            transform: (String) -> String) -> String {
        let opts: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive, .dotMatchesLineSeparators] : [.dotMatchesLineSeparators]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: opts) else { return input }
        let nsInput = input as NSString
        var result = ""
        var lastEnd = 0
        let range = NSRange(location: 0, length: nsInput.length)
        regex.enumerateMatches(in: input, range: range) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            let whole = match.range(at: 0)
            let captured = nsInput.substring(with: match.range(at: 1))
            result += nsInput.substring(with: NSRange(location: lastEnd, length: whole.location - lastEnd))
            result += transform(captured)
            lastEnd = whole.location + whole.length
        }
        result += nsInput.substring(from: lastEnd)
        return result
    }
}
