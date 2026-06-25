import SwiftUI

/// A parsed Markdown block (Issue 4). Parsing is pure + testable; rendering is in
/// `ChatMarkdownView`. We deliberately support a SAFE subset — no raw HTML/script
/// execution.
public enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet([String])
    case numbered([String])
    case codeBlock(String)
    case rule
}

public enum ChatMarkdown {

    /// Split assistant text into blocks: fenced code, ATX headings (`#`..`######`),
    /// horizontal rules (`---`/`***`), bullet (`- `/`* `) and numbered (`1. `) lists,
    /// and paragraphs. Consecutive list items / paragraph lines are grouped.
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        var paragraph: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []
        var inCode = false
        var code: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        func flushBullets() { if !bullets.isEmpty { blocks.append(.bullet(bullets)); bullets = [] } }
        func flushNumbers() { if !numbers.isEmpty { blocks.append(.numbered(numbers)); numbers = [] } }
        func flushAll() { flushParagraph(); flushBullets(); flushNumbers() }

        for rawLine in lines {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode { blocks.append(.codeBlock(code.joined(separator: "\n"))); code = []; inCode = false }
                else { flushAll(); inCode = true }
                continue
            }
            if inCode { code.append(line); continue }

            if trimmed.isEmpty { flushAll(); continue }

            // Horizontal rule: a line of only - or * (3+).
            if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "-" }) || trimmed.allSatisfy({ $0 == "*" }) {
                flushAll(); blocks.append(.rule); continue
            }
            // ATX heading (`#`..`######` followed by a space).
            if trimmed.hasPrefix("#") {
                let hashCount = trimmed.prefix(while: { $0 == "#" }).count
                if hashCount <= 6, trimmed.dropFirst(hashCount).first == " " {
                    flushAll()
                    let content = String(trimmed.dropFirst(hashCount).drop(while: { $0 == " " }))
                    blocks.append(.heading(level: hashCount, text: content))
                    continue
                }
            }
            // Bullet item.
            if let r = trimmed.range(of: "^([-*])\\s+", options: .regularExpression) {
                flushParagraph(); flushNumbers()
                bullets.append(String(trimmed[r.upperBound...])); continue
            }
            // Numbered item.
            if let r = trimmed.range(of: "^[0-9]+[.)]\\s+", options: .regularExpression) {
                flushParagraph(); flushBullets()
                numbers.append(String(trimmed[r.upperBound...])); continue
            }
            // Paragraph line.
            flushBullets(); flushNumbers()
            paragraph.append(trimmed)
        }
        if inCode, !code.isEmpty { blocks.append(.codeBlock(code.joined(separator: "\n"))) }
        flushAll()
        return blocks
    }

    /// Inline formatting (**bold**, *italic*, `code`, [links]) as an AttributedString.
    /// Uses Foundation's inline-only Markdown — it does NOT execute HTML or scripts.
    public static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

/// Renders assistant Markdown safely with language-aware RTL alignment (Issue 4).
struct ChatMarkdownView: View {
    let text: String
    var language: AILanguage = .automatic

    private func rtl(_ s: String) -> Bool { TextDirection.isRTL(language: language, text: s) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(ChatMarkdown.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let t):
            aligned(Text(ChatMarkdown.inline(t)).font(headingFont(level)).bold(), rtl(t))
        case .paragraph(let t):
            aligned(Text(ChatMarkdown.inline(t)), rtl(t))
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items, id: \.self) { item in aligned(Text("• ") + Text(ChatMarkdown.inline(item)), rtl(item)) }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    aligned(Text("\(i + 1). ") + Text(ChatMarkdown.inline(item)), rtl(item))
                }
            }
        case .codeBlock(let c):
            Text(c).font(.system(.footnote, design: .monospaced))
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 6))
        case .rule:
            Divider()
        }
    }

    private func aligned(_ text: Text, _ isRTL: Bool) -> some View {
        text.multilineTextAlignment(isRTL ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level { case 1: return .title2; case 2: return .title3; case 3: return .headline; default: return .subheadline }
    }
}
