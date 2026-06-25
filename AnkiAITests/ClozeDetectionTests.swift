import XCTest
@testable import AnkiAI

/// M2.38 — auto-detect cloze syntax so AI-generated/added cards become Cloze notes.
final class ClozeDetectionTests: XCTestCase {

    func testDetectsClozeSyntax() {
        XCTAssertTrue(AIChatViewModel.containsCloze("The capital is {{c1::Paris}}."))
        XCTAssertTrue(AIChatViewModel.containsCloze("{{c2::H2O}} is water"))
        XCTAssertTrue(AIChatViewModel.containsCloze("a {{c1::b::hint}} c"))
    }

    func testIgnoresNonCloze() {
        XCTAssertFalse(AIChatViewModel.containsCloze("Plain front"))
        XCTAssertFalse(AIChatViewModel.containsCloze("{{Front}} template field"))
        XCTAssertFalse(AIChatViewModel.containsCloze("c1::not braced"))
        XCTAssertFalse(AIChatViewModel.containsCloze(""))
    }
}
