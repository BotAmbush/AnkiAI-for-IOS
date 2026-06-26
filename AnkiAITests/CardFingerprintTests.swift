import XCTest
@testable import AnkiAI

/// Repair 3 — normalized card fingerprint for duplicate detection.
final class CardFingerprintTests: XCTestCase {

    func testNormalizeStripsHTMLAndCollapsesWhitespace() {
        XCTAssertEqual(CardFingerprint.normalize("<b>Hello</b>   world\n"), "hello world")
        XCTAssertEqual(CardFingerprint.normalize("a&nbsp;&amp;&nbsp;b"), "a & b")
    }

    func testWhitespaceAndHTMLOnlyDifferencesAreSameFingerprint() {
        let a = CardFingerprint.make(notetypeId: 1, deckId: 2, fields: ["<div>What is 2+2?</div>", "4"])
        let b = CardFingerprint.make(notetypeId: 1, deckId: 2, fields: ["What   is 2+2?", "<b>4</b>"])
        XCTAssertEqual(a, b)
    }

    func testGenuinelyDifferentContentDiffers() {
        let a = CardFingerprint.make(notetypeId: 1, deckId: 2, fields: ["Q1", "A1"])
        let b = CardFingerprint.make(notetypeId: 1, deckId: 2, fields: ["Q2", "A1"])
        XCTAssertNotEqual(a, b)
    }

    func testDifferentDeckOrTypeDiffers() {
        let base = CardFingerprint.make(notetypeId: 1, deckId: 2, fields: ["Q", "A"])
        XCTAssertNotEqual(base, CardFingerprint.make(notetypeId: 1, deckId: 3, fields: ["Q", "A"]))
        XCTAssertNotEqual(base, CardFingerprint.make(notetypeId: 9, deckId: 2, fields: ["Q", "A"]))
    }

    func testTagsAffectFingerprintOrderIndependently() {
        let a = CardFingerprint.make(notetypeId: 1, deckId: 2, fields: ["Q", "A"], tags: ["x", "y"])
        let b = CardFingerprint.make(notetypeId: 1, deckId: 2, fields: ["Q", "A"], tags: ["y", "x"])
        XCTAssertEqual(a, b, "tag order does not matter")
        let c = CardFingerprint.make(notetypeId: 1, deckId: 2, fields: ["Q", "A"], tags: ["z"])
        XCTAssertNotEqual(a, c)
    }
}
