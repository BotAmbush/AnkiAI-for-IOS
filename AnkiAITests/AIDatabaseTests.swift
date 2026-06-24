import XCTest
@testable import AnkiAI

final class AIDatabaseTests: XCTestCase {

    func testInsertAndFetchMessages() throws {
        let db = try AIDatabase(path: ":memory:")
        try db.insert(AIChatMessage(sessionId: "card_1", role: "user", content: "hi", timestamp: 1))
        try db.insert(AIChatMessage(sessionId: "card_1", role: "assistant", content: "hello", timestamp: 2))
        try db.insert(AIChatMessage(sessionId: "card_2", role: "user", content: "other", timestamp: 3))

        let msgs = try db.messages(sessionId: "card_1")
        XCTAssertEqual(msgs.count, 2)
        XCTAssertEqual(msgs[0].content, "hi")
        XCTAssertEqual(msgs[1].content, "hello")
    }

    func testMessagesOrderedByTimestamp() throws {
        let db = try AIDatabase(path: ":memory:")
        try db.insert(AIChatMessage(sessionId: "s", role: "user", content: "second", timestamp: 200))
        try db.insert(AIChatMessage(sessionId: "s", role: "user", content: "first", timestamp: 100))
        let msgs = try db.messages(sessionId: "s")
        XCTAssertEqual(msgs.map { $0.content }, ["first", "second"])
    }

    func testDeleteSession() throws {
        let db = try AIDatabase(path: ":memory:")
        try db.insert(AIChatMessage(sessionId: "s", role: "user", content: "x", timestamp: 1))
        try db.deleteSession("s")
        XCTAssertTrue(try db.messages(sessionId: "s").isEmpty)
    }

    func testMetadataAndTypePersisted() throws {
        let db = try AIDatabase(path: ":memory:")
        try db.insert(AIChatMessage(sessionId: "s", role: "assistant", content: "prop",
                                    messageType: AIChatMessage.typeEditProposal,
                                    metadata: #"{"action":"edit_card"}"#, timestamp: 1))
        let msg = try XCTUnwrap(try db.messages(sessionId: "s").first)
        XCTAssertEqual(msg.messageType, AIChatMessage.typeEditProposal)
        XCTAssertEqual(msg.metadata, #"{"action":"edit_card"}"#)
    }
}
