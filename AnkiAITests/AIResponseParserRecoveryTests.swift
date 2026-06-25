import XCTest
@testable import AnkiAI

/// Issue 5 — robust local recovery of the creator card list from common valid
/// model variations, with partial-success handling.
final class AIResponseParserRecoveryTests: XCTestCase {

    private func parse(_ s: String) -> AIResponseParser.CardParseOutcome? {
        AIResponseParser.parseGeneratedCards(s)
    }

    func testPlainArray() {
        let o = parse(#"[{"front":"Q1","back":"A1","deckName":"Math"}]"#)
        XCTAssertEqual(o?.cards.count, 1)
        XCTAssertEqual(o?.cards.first?.front, "Q1")
        XCTAssertEqual(o?.cards.first?.deckName, "Math")
    }

    func testFencedJSON() {
        let o = parse("Here you go:\n```json\n[{\"front\":\"Q\",\"back\":\"A\",\"deckName\":\"D\"}]\n```\nEnjoy!")
        XCTAssertEqual(o?.cards.count, 1)
        XCTAssertEqual(o?.stage, "fenced")
    }

    func testProseAroundArray() {
        let o = parse("Sure! [{\"front\":\"Q\",\"back\":\"A\"}] — let me know.")
        XCTAssertEqual(o?.cards.count, 1)
    }

    func testCardsEnvelopeObject() {
        let o = parse(#"{"schemaVersion":1,"cards":[{"front":"Q","back":"A","deck":"D"}]}"#)
        XCTAssertEqual(o?.cards.count, 1)
        XCTAssertEqual(o?.cards.first?.deckName, "D")
    }

    func testSingleCardObject() {
        let o = parse(#"{"front":"Q","back":"A","deckName":"D"}"#)
        XCTAssertEqual(o?.cards.count, 1)
    }

    func testFrontHtmlAndBackHtmlKeys() {
        let o = parse(#"[{"front_html":"<b>Q</b>","back_html":"<i>A</i>","deckName":"D"}]"#)
        XCTAssertEqual(o?.cards.first?.front, "<b>Q</b>")
        XCTAssertEqual(o?.cards.first?.back, "<i>A</i>")
    }

    func testHebrewHtmlAndMathJaxPreserved() {
        let json = #"[{"front":"<div dir=\"rtl\">שאלה</div>","back":"<span dir=\"ltr\">\\(E=mc^2\\)</span>","deckName":"פיזיקה"}]"#
        let o = parse(json)
        XCTAssertEqual(o?.cards.count, 1)
        XCTAssertTrue(o?.cards.first?.front.contains("rtl") ?? false)
        XCTAssertTrue(o?.cards.first?.back.contains("E=mc^2") ?? false)
        XCTAssertEqual(o?.cards.first?.deckName, "פיזיקה")
    }

    func testBOMStripped() {
        let o = parse("\u{FEFF}[{\"front\":\"Q\",\"back\":\"A\"}]")
        XCTAssertEqual(o?.cards.count, 1)
    }

    func testMalformedOneCardKeepsValidOnes() {
        // second element is not an object; third is missing a front
        let o = parse(#"[{"front":"Q1","back":"A1"}, "oops", {"back":"only back"}]"#)
        XCTAssertEqual(o?.cards.count, 1, "valid card preserved")
        XCTAssertEqual(o?.skipped.count, 2, "two cards reported as skipped")
    }

    func testEntirelyMalformedReturnsNil() {
        XCTAssertNil(parse("this is not json at all, sorry"))
    }

    func testEmptyAndTruncatedReturnNil() {
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("   \n  "))
        XCTAssertNil(parse(#"[{"front":"Q","back":"A"#))  // truncated
    }

    func testEmptyArrayReturnsNil() {
        XCTAssertNil(parse("[]"))
    }
}
