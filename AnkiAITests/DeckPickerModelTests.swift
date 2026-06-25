import XCTest
@testable import AnkiAI

/// Issue 1 — unambiguous hierarchical deck selection.
final class DeckPickerModelTests: XCTestCase {

    private let decks = [
        DeckNameId(id: 1, name: "Default"),
        DeckNameId(id: 2, name: "University::Physics 101::Chapter 1::Review"),
        DeckNameId(id: 3, name: "University::Chemistry::Chapter 1::Review"),
        DeckNameId(id: 4, name: "אוניברסיטה::פיזיקה::פרק 1"),
        DeckNameId(id: 5, name: "Languages::Hebrew vocabulary"),
    ]

    func testLeafAndParentPath() {
        XCTAssertEqual(DeckPickerModel.leaf("University::Physics 101::Chapter 1::Review"), "Review")
        XCTAssertEqual(DeckPickerModel.parentPath("University::Physics 101::Chapter 1::Review"),
                       "University › Physics 101 › Chapter 1")
        XCTAssertEqual(DeckPickerModel.parentPath("Default"), "")
    }

    func testTwoDecksShareLeafButDifferentParents() {
        // Both end in "Review" — the parent path is what distinguishes them.
        let a = decks[1], b = decks[2]
        XCTAssertEqual(DeckPickerModel.leaf(a.name), DeckPickerModel.leaf(b.name))
        XCTAssertNotEqual(DeckPickerModel.parentPath(a.name), DeckPickerModel.parentPath(b.name))
    }

    func testHebrewDeckPath() {
        XCTAssertEqual(DeckPickerModel.leaf("אוניברסיטה::פיזיקה::פרק 1"), "פרק 1")
        XCTAssertEqual(DeckPickerModel.parentPath("אוניברסיטה::פיזיקה::פרק 1"), "אוניברסיטה › פיזיקה")
    }

    func testSearchByParentName() {
        let r = DeckPickerModel.filter(decks, query: "physics")
        XCTAssertEqual(r.map { $0.id }, [2])
    }

    func testSearchByChildName() {
        let r = DeckPickerModel.filter(decks, query: "review")
        XCTAssertEqual(Set(r.map { $0.id }), [2, 3])
    }

    func testSearchHebrew() {
        let r = DeckPickerModel.filter(decks, query: "פיזיקה")
        XCTAssertEqual(r.map { $0.id }, [4])
    }

    func testEmptyQueryReturnsAll() {
        XCTAssertEqual(DeckPickerModel.filter(decks, query: "  ").count, decks.count)
    }
}
