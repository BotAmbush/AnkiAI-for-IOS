import XCTest
import CryptoKit
@testable import AnkiAI

/// M2.2 integration tests: list real cards in a deck and render their
/// question/answer + note-type CSS through the Anki backend, while proving the
/// canonical fixture is never mutated (operations run on a copy).
final class BackendRenderTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func dirHash(_ dir: URL) throws -> String {
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var hasher = SHA256()
        for f in files {
            hasher.update(data: Data(f.lastPathComponent.utf8))
            hasher.update(data: try Data(contentsOf: f))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Create a fixture and return a gateway opened on a COPY, plus the original hash.
    private func openedCopy() throws -> (gateway: BackendCollectionGateway, fixtureDir: URL, originalHash: String) {
        let fixtureDir = try makeTempDir()
        try AnkiCollection.createFixture(path: fixtureDir.appendingPathComponent("collection.anki2").path)
        let originalHash = try dirHash(fixtureDir)
        let copyDir = try makeTempDir()
        for f in try FileManager.default.contentsOfDirectory(at: fixtureDir, includingPropertiesForKeys: nil) {
            try FileManager.default.copyItem(at: f, to: copyDir.appendingPathComponent(f.lastPathComponent))
        }
        let gateway = BackendCollectionGateway(path: copyDir.appendingPathComponent("collection.anki2").path)
        return (gateway, fixtureDir, originalHash)
    }

    func testDeckHasRealCardIds() async throws {
        let (gateway, fixtureDir, originalHash) = try openedCopy()
        let heb = try await gateway.cardIds(inDeckNamed: "Languages::Hebrew")
        XCTAssertFalse(heb.isEmpty, "Hebrew deck should have cards")
        let math = try await gateway.cardIds(inDeckNamed: "Math")
        XCTAssertFalse(math.isEmpty, "Math deck should have cards")
        XCTAssertEqual(try dirHash(fixtureDir), originalHash, "listing must not mutate the original")
    }

    func testRenderHebrewCardPreservesRTLAndCSS() async throws {
        let (gateway, fixtureDir, originalHash) = try openedCopy()
        let ids = try await gateway.cardIds(inDeckNamed: "Languages::Hebrew")
        var anyRTL = false
        for id in ids {
            let card = try await gateway.renderCard(cardId: id)
            XCTAssertFalse(card.questionHTML.isEmpty)
            XCTAssertFalse(card.answerHTML.isEmpty)
            XCTAssertTrue(card.css.contains(".card"), "note-type CSS should include .card")
            if card.questionHTML.contains("dir=\"rtl\"") { anyRTL = true }
        }
        XCTAssertTrue(anyRTL, "at least one Hebrew card question should preserve dir=\"rtl\"")
        XCTAssertEqual(try dirHash(fixtureDir), originalHash, "rendering must not mutate the original")
    }

    func testRenderMathCardKeepsMathJaxDelimiters() async throws {
        let (gateway, _, _) = try openedCopy()
        let ids = try await gateway.cardIds(inDeckNamed: "Math")
        var anyMath = false
        for id in ids {
            let card = try await gateway.renderCard(cardId: id)
            // The calculus fixture cards use \( ... \) inline math.
            if card.questionHTML.contains("\\(") || card.answerHTML.contains("\\[") { anyMath = true }
        }
        XCTAssertTrue(anyMath, "at least one Math card should keep \\( or \\[ MathJax delimiters")
    }

    func testAnswerContainsBackContent() async throws {
        let (gateway, _, _) = try openedCopy()
        let ids = try await gateway.cardIds(inDeckNamed: "Math")
        let card = try await gateway.renderCard(cardId: try XCTUnwrap(ids.first))
        // Default Basic afmt is {{FrontSide}}<hr id=answer>{{Back}} — answer differs from question.
        XCTAssertNotEqual(card.questionHTML, card.answerHTML)
        XCTAssertTrue(card.answerHTML.contains("hr"), "answer should include the front/back separator")
    }
}
