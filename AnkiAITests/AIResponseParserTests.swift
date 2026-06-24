import XCTest
@testable import AnkiAI

final class AIResponseParserTests: XCTestCase {

    func testExtractJSONObjectPlain() {
        let s = #"{"action":"edit_card","fieldName":"Front"}"#
        XCTAssertEqual(AIResponseParser.extractJSONObject(s), s)
    }

    func testExtractJSONObjectFenced() {
        let s = "Here you go:\n```json\n{\"action\":\"edit_card\"}\n```\nDone."
        XCTAssertEqual(AIResponseParser.extractJSONObject(s), "{\"action\":\"edit_card\"}")
    }

    func testExtractJSONArrayBareBrackets() {
        let s = "prefix [ {\"front\":\"a\"} ] suffix"
        XCTAssertEqual(AIResponseParser.extractJSONArray(s), "[ {\"front\":\"a\"} ]")
    }

    func testInterpretEditCard() {
        let reply = #"{"action":"edit_card","fieldName":"Back","newContent":"<b>x</b>","explanation":"clearer"}"#
        guard case let .editCard(field, content, expl) = AIResponseParser.interpretReviewerReply(reply) else {
            return XCTFail("expected editCard")
        }
        XCTAssertEqual(field, "Back")
        XCTAssertEqual(content, "<b>x</b>")
        XCTAssertEqual(expl, "clearer")
    }

    func testInterpretAddCard() {
        let reply = #"{"action":"add_card","front":"Q","back":"A","deckName":"Physics::Quantum","explanation":"why"}"#
        guard case let .addCard(front, back, deck, _) = AIResponseParser.interpretReviewerReply(reply) else {
            return XCTFail("expected addCard")
        }
        XCTAssertEqual(front, "Q")
        XCTAssertEqual(back, "A")
        XCTAssertEqual(deck, "Physics::Quantum")
    }

    func testInterpretPlainTextWhenNotJSON() {
        guard case let .text(t) = AIResponseParser.interpretReviewerReply("Just an explanation.") else {
            return XCTFail("expected text")
        }
        XCTAssertEqual(t, "Just an explanation.")
    }

    func testInterpretMalformedJSONFallsBackToText() {
        let reply = "{not valid json"
        guard case .text = AIResponseParser.interpretReviewerReply(reply) else {
            return XCTFail("expected text fallback")
        }
    }

    func testParseGeneratedCardsPrefersHtmlVariant() {
        let reply = """
        [
          {"front_html":"<b>F1</b>","back_html":"<b>B1</b>","deckName":"Default"},
          {"front":"F2","back":"B2","deckName":"Physics"}
        ]
        """
        let cards = AIResponseParser.parseGeneratedCards(reply)
        XCTAssertEqual(cards?.count, 2)
        XCTAssertEqual(cards?[0].front, "<b>F1</b>")
        XCTAssertEqual(cards?[1].front, "F2")
        XCTAssertEqual(cards?[1].deckName, "Physics")
    }

    func testParseGeneratedCardsDefaultsDeck() {
        let cards = AIResponseParser.parseGeneratedCards(#"[{"front":"a","back":"b"}]"#)
        XCTAssertEqual(cards?.first?.deckName, "Default")
    }

    func testParseGeneratedCardsReturnsNilOnGarbage() {
        XCTAssertNil(AIResponseParser.parseGeneratedCards("no json here"))
    }
}
