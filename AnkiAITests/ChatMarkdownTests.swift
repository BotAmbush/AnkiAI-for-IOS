import XCTest
@testable import AnkiAI

/// Issue 4 — safe Markdown block parsing for assistant chat messages.
final class ChatMarkdownTests: XCTestCase {

    func testHeadings() {
        XCTAssertEqual(ChatMarkdown.parse("# Title"), [.heading(level: 1, text: "Title")])
        XCTAssertEqual(ChatMarkdown.parse("## H2"), [.heading(level: 2, text: "H2")])
        XCTAssertEqual(ChatMarkdown.parse("### H3"), [.heading(level: 3, text: "H3")])
    }

    func testHebrewHeadingAndBold() {
        let blocks = ChatMarkdown.parse("## כותרת בעברית\n**טקסט מודגש**")
        XCTAssertEqual(blocks.first, .heading(level: 2, text: "כותרת בעברית"))
        XCTAssertEqual(blocks.last, .paragraph("**טקסט מודגש**"))
    }

    func testHorizontalRule() {
        XCTAssertEqual(ChatMarkdown.parse("a\n\n---\n\nb"),
                       [.paragraph("a"), .rule, .paragraph("b")])
    }

    func testBulletList() {
        XCTAssertEqual(ChatMarkdown.parse("- one\n- two\n* three"),
                       [.bullet(["one", "two", "three"])])
    }

    func testNumberedList() {
        XCTAssertEqual(ChatMarkdown.parse("1. first\n2. second\n3) third"),
                       [.numbered(["first", "second", "third"])])
    }

    func testCodeBlock() {
        XCTAssertEqual(ChatMarkdown.parse("```\nlet x = 1\n```"),
                       [.codeBlock("let x = 1")])
    }

    func testMixedDocument() {
        let md = "# Heading\nintro line\n\n- a\n- b\n\n1. one\n2. two\n\n---\nfinal"
        let blocks = ChatMarkdown.parse(md)
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Heading"),
            .paragraph("intro line"),
            .bullet(["a", "b"]),
            .numbered(["one", "two"]),
            .rule,
            .paragraph("final"),
        ])
    }

    func testBinaryNumberAndLatinStayAsParagraph() {
        XCTAssertEqual(ChatMarkdown.parse("The value is 101.1₂ and E = mc^2"),
                       [.paragraph("The value is 101.1₂ and E = mc^2")])
    }

    func testInlineDoesNotCrashAndStripsBold() {
        let a = ChatMarkdown.inline("**bold** and *italic* and `code`")
        XCTAssertFalse(String(a.characters).contains("**"), "bold markers consumed")
    }

    func testHashWithoutSpaceIsNotHeading() {
        XCTAssertEqual(ChatMarkdown.parse("#hashtag"), [.paragraph("#hashtag")])
    }
}
