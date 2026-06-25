import XCTest
@testable import AnkiAI

/// M2.30: locale-driven localization (Hebrew catalog ported from the Android fork).
final class LocalizationTests: XCTestCase {

    func testHebrewTranslations() {
        XCTAssertEqual(Loc.t("Send", lang: "he"), "שלח")
        XCTAssertEqual(Loc.t("Show Answer", lang: "he"), "הצג תשובה")
        XCTAssertEqual(Loc.t("Decks", lang: "he"), "חפיסות")
        XCTAssertEqual(Loc.t("Again", lang: "he"), "שוב")
        XCTAssertEqual(Loc.t("Settings", lang: "he"), "הגדרות")
    }

    func testEnglishReturnsKey() {
        XCTAssertEqual(Loc.t("Send", lang: "en"), "Send")
        XCTAssertEqual(Loc.t("Show Answer", lang: "en"), "Show Answer")
    }

    func testUnmappedKeyFallsBackToItself() {
        XCTAssertEqual(Loc.t("Totally Unmapped String", lang: "he"), "Totally Unmapped String")
    }

    func testLegacyHebrewCodeIwIsTreatedAsHebrew() {
        XCTAssertEqual(Loc.t("Send", lang: "iw"), "שלח")
    }
}
