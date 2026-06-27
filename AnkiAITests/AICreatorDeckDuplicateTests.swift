import XCTest
@testable import AnkiAI

/// Repairs 1 + 3 — creator deck selection (persisted, explicit, verified) and
/// accepted-card duplicate prevention.
@MainActor
final class AICreatorDeckDuplicateTests: XCTestCase {

    override func setUp() { CreatorSessionStore.clear(sessionId: "creator") }
    override func tearDown() { CreatorSessionStore.clear(sessionId: "creator") }

    private func makeCreator(reply: String) throws -> (AIChatViewModel, StubCollectionGateway) {
        let db = try AIDatabase(path: ":memory:")
        let settings = AISettingsStore(keychain: InMemorySecretStore(),
                                       defaults: UserDefaults(suiteName: "cd-\(UUID().uuidString)")!)
        settings.apiKey = "sk-ant-test"
        let gateway = StubCollectionGateway()
        let fake = FakeChatClient(reply: .success(reply))
        let vm = AIChatViewModel(cardId: -1, gateway: gateway, db: db, settings: settings,
                                 clientFactory: { _, _ in fake })
        return (vm, gateway)
    }

    private let oneCard = #"[{"front":"Capital of France?","back":"Paris","deckName":"Default"}]"#

    func testSelectedDeckPersistsAndRestores() async throws {
        let (vm1, _) = try makeCreator(reply: oneCard)
        await vm1.load()
        vm1.setCreatorDeck(id: 2, path: "Physics")
        XCTAssertEqual(vm1.selectedDeckId, 2)

        let (vm2, _) = try makeCreator(reply: oneCard)
        await vm2.load()
        XCTAssertEqual(vm2.selectedDeckId, 2)
        XCTAssertEqual(vm2.selectedDeckPath, "Physics")
    }

    func testCardAddedToSelectedDeckNotModelDeck() async throws {
        let (vm, gateway) = try makeCreator(reply: oneCard)   // model says "Default" (id 1)
        await vm.load()
        vm.setCreatorDeck(id: 2, path: "Physics")             // user chose Physics (id 2)
        await vm.generateCards("x")
        let proposal = try XCTUnwrap(vm.generationProposals.first)
        await vm.addCardFromProposal(proposal)
        XCTAssertEqual(vm.addedCount, 1)
        let addedDeck = await gateway.lastAddedDeckId
        XCTAssertEqual(addedDeck, 2, "uses the user's selected deck, not the model's")
    }

    func testNoSelectedDeckBlocksGeneration() async throws {
        let (vm, _) = try makeCreator(reply: oneCard)
        await vm.load()
        // No setCreatorDeck → generation must be blocked, no API/proposals.
        await vm.generateCards("x")
        XCTAssertTrue(vm.generationProposals.isEmpty)
        XCTAssertEqual(vm.addedCount, 0)
        XCTAssertTrue(vm.error?.localizedCaseInsensitiveContains("select a destination deck") ?? false)
    }

    func testNoSelectedDeckBlocksInsertion() async throws {
        let (vm, _) = try makeCreator(reply: oneCard)
        await vm.load()
        let proposal = CardProposal(front: "Q", back: "A", deckName: "Physics", deckId: 2)
        await vm.addCardFromProposal(proposal)   // no selected deck
        XCTAssertEqual(vm.addedCount, 0)
        XCTAssertTrue(vm.error?.localizedCaseInsensitiveContains("select a destination deck") ?? false)
    }

    func testDeletedSelectedDeckBlocksGenerationAndClearsSelection() async throws {
        let (vm, _) = try makeCreator(reply: oneCard)
        await vm.load()
        vm.setCreatorDeck(id: 9999, path: "Ghost")   // a deck that does not exist (deleted)
        await vm.generateCards("x")
        XCTAssertTrue(vm.generationProposals.isEmpty)
        XCTAssertNil(vm.selectedDeckId, "deleted deck selection is cleared")
        XCTAssertTrue(vm.error?.localizedCaseInsensitiveContains("no longer exists") ?? false)
    }

    func testDeletedSelectedDeckBlocksAdd() async throws {
        let (vm, _) = try makeCreator(reply: oneCard)
        await vm.load()
        let proposal = CardProposal(front: "Q", back: "A", deckName: "Physics", deckId: 2)
        vm.setCreatorDeck(id: 8888, path: "Ghost")   // selection points at a missing deck
        await vm.addCardFromProposal(proposal)
        XCTAssertEqual(vm.addedCount, 0)
        XCTAssertTrue(vm.error?.localizedCaseInsensitiveContains("deck") ?? false)
    }

    func testAcceptThenRegenerateDoesNotDuplicate() async throws {
        let (vm, _) = try makeCreator(reply: oneCard)
        await vm.load()
        vm.setCreatorDeck(id: 2, path: "Physics")
        await vm.generateCards("x")
        await vm.addCardFromProposal(try XCTUnwrap(vm.generationProposals.first))
        XCTAssertEqual(vm.addedCount, 1)

        await vm.regenerate()                                 // same content again
        let dup = try XCTUnwrap(vm.generationProposals.first)
        XCTAssertTrue(vm.isDuplicate(dup))
        await vm.addCardFromProposal(dup)                     // should be blocked
        XCTAssertEqual(vm.addedCount, 1, "duplicate not silently added")
        XCTAssertNotNil(vm.duplicatePending)

        await vm.confirmAddDuplicate(dup)                     // explicit override
        XCTAssertEqual(vm.addedCount, 2)
    }

    func testDuplicateLedgerSurvivesRelaunch() async throws {
        let (vm1, _) = try makeCreator(reply: oneCard)
        await vm1.load()
        vm1.setCreatorDeck(id: 2, path: "Physics")
        await vm1.generateCards("x")
        await vm1.addCardFromProposal(try XCTUnwrap(vm1.generationProposals.first))

        let (vm2, _) = try makeCreator(reply: oneCard)
        await vm2.load()
        await vm2.generateCards("x")
        let dup = try XCTUnwrap(vm2.generationProposals.first)
        XCTAssertTrue(vm2.isDuplicate(dup), "accepted fingerprints restored after relaunch")
    }

    func testWhitespaceHTMLVariantIsDuplicate() async throws {
        let (vm, _) = try makeCreator(reply: oneCard)
        await vm.load()
        vm.setCreatorDeck(id: 2, path: "Physics")
        await vm.generateCards("x")
        await vm.addCardFromProposal(try XCTUnwrap(vm.generationProposals.first))
        // Same card with HTML/whitespace noise.
        let variant = CardProposal(front: "  <div>Capital of France?</div> ", back: "<b>Paris</b>",
                                   deckName: "Physics", deckId: 2)
        XCTAssertTrue(vm.isDuplicate(variant))
    }

    func testGenuinelyDifferentCardNotDuplicate() async throws {
        let (vm, _) = try makeCreator(reply: oneCard)
        await vm.load()
        vm.setCreatorDeck(id: 2, path: "Physics")
        await vm.generateCards("x")
        await vm.addCardFromProposal(try XCTUnwrap(vm.generationProposals.first))
        let other = CardProposal(front: "Capital of Spain?", back: "Madrid", deckName: "Physics", deckId: 2)
        XCTAssertFalse(vm.isDuplicate(other))
    }

    func testFailedInsertDoesNotRecordFingerprint() async throws {
        let (vm, _) = try makeCreator(reply: oneCard)
        await vm.load()
        vm.setCreatorDeck(id: 2, path: "Physics")
        await vm.generateCards("x")
        let p = try XCTUnwrap(vm.generationProposals.first)
        // Point the deck at a missing one so the add fails the existence check.
        vm.setCreatorDeck(id: 8888, path: "Ghost")
        await vm.addCardFromProposal(p)
        XCTAssertEqual(vm.addedCount, 0)
        vm.setCreatorDeck(id: 2, path: "Physics")
        XCTAssertFalse(vm.isDuplicate(p), "no fingerprint recorded for a failed insert")
    }
}
