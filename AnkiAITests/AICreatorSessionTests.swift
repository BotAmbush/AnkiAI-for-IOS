import XCTest
@testable import AnkiAI

/// Issue 3 — the unfinished AI creator session (proposals, draft, language,
/// attachments) survives dismissal and relaunch; Clear removes it without deleting
/// accepted cards.
@MainActor
final class AICreatorSessionTests: XCTestCase {

    override func setUp() { CreatorSessionStore.clear(sessionId: "creator") }
    override func tearDown() { CreatorSessionStore.clear(sessionId: "creator") }

    private func makeCreator(reply: String) throws -> AIChatViewModel {
        let db = try AIDatabase(path: ":memory:")
        let settings = AISettingsStore(keychain: InMemorySecretStore(),
                                       defaults: UserDefaults(suiteName: "cs-\(UUID().uuidString)")!)
        settings.apiKey = "sk-ant-test"
        let fake = FakeChatClient(reply: .success(reply))
        return AIChatViewModel(cardId: -1, gateway: StubCollectionGateway(), db: db,
                               settings: settings, clientFactory: { _, _ in fake })
    }

    func testGeneratedProposalsRestoreAfterRelaunch() async throws {
        let json = #"[{"front":"Q1","back":"A1","deckName":"Default"},{"front":"Q2","back":"A2","deckName":"Default"}]"#
        let vm1 = try makeCreator(reply: json)
        await vm1.load()
        vm1.setCreatorDeck(id: 2, path: "Physics")
        await vm1.generateCards("make cards")
        XCTAssertEqual(vm1.generationProposals.count, 2)

        // Fresh VM with the same fixed creator session id = "relaunch".
        let vm2 = try makeCreator(reply: "")
        await vm2.load()
        XCTAssertEqual(vm2.generationProposals.count, 2, "pending proposals restored")
        XCTAssertEqual(vm2.generationProposals.first?.front, "Q1")
    }

    func testDraftAndLanguageRestore() async throws {
        let vm1 = try makeCreator(reply: "")
        await vm1.load()
        vm1.draft = "binary representation of 5"
        vm1.setLanguage(.hebrew)
        vm1.persistSession()

        let vm2 = try makeCreator(reply: "")
        await vm2.load()
        XCTAssertEqual(vm2.draft, "binary representation of 5")
        XCTAssertEqual(vm2.language, .hebrew)
    }

    func testClearSessionRemovesPersistedProposals() async throws {
        let json = #"[{"front":"Q","back":"A","deckName":"Default"}]"#
        let vm1 = try makeCreator(reply: json)
        await vm1.load()
        vm1.setCreatorDeck(id: 2, path: "Physics")
        await vm1.generateCards("x")
        XCTAssertEqual(vm1.generationProposals.count, 1)
        vm1.clearSession()

        let vm2 = try makeCreator(reply: "")
        await vm2.load()
        XCTAssertTrue(vm2.generationProposals.isEmpty, "cleared session restores nothing")
        XCTAssertEqual(vm2.draft, "")
    }

    func testParseFailurePreservesSessionForRetry() async throws {
        let vm1 = try makeCreator(reply: "I cannot do that as JSON, sorry.")
        await vm1.load()
        vm1.setCreatorDeck(id: 2, path: "Physics")
        await vm1.generateCards("make cards")
        XCTAssertTrue(vm1.parseFailed, "unparseable response flags failure")
        XCTAssertTrue(vm1.generationProposals.isEmpty)

        // The failure state + prompt is preserved across relaunch.
        let vm2 = try makeCreator(reply: "")
        await vm2.load()
        XCTAssertTrue(vm2.parseFailed, "parse-failure state persisted (session not lost)")
    }

    func testStoreRoundTripWithMetadataAttachments() {
        let id = "rt-\(UUID().uuidString)"
        var s = PersistedCreatorSession()
        s.draft = "hello"; s.language = "hebrew"; s.repairAttempted = true
        s.selectedDeckId = 7; s.selectedDeckPath = "A::B"
        s.proposals = [PersistedProposal(front: "F", back: "B", deckName: "D", deckId: 5)]
        s.attachments = [CreatorAttachmentRef(id: "a1", filename: "a1.png", contentType: "image/png",
                                              byteSize: 10, sha256: "abc", createdAt: Date(timeIntervalSince1970: 1))]
        s.acceptedFingerprints = ["fp1"]
        CreatorSessionStore.save(s, sessionId: id)
        XCTAssertEqual(CreatorSessionStore.load(sessionId: id), s)
        CreatorSessionStore.clear(sessionId: id)
        XCTAssertNil(CreatorSessionStore.load(sessionId: id))
    }

    func testSessionJSONContainsNoBase64AttachmentPayload() throws {
        let id = "nob64-\(UUID().uuidString)"
        var s = PersistedCreatorSession()
        s.attachments = [CreatorAttachmentRef(id: "a1", filename: "a1.png", contentType: "image/png",
                                              byteSize: 4, sha256: "deadbeef", createdAt: Date())]
        CreatorSessionStore.save(s, sessionId: id)
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = base.appendingPathComponent("AICreatorSessions").appendingPathComponent("\(id).json")
        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(json.contains("base64"), "session JSON must not carry attachment bytes")
        CreatorSessionStore.clear(sessionId: id)
    }
}
