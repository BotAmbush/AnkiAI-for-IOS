import XCTest
@testable import AnkiAI

/// Repair 2 — reviewer add-card deck resolution: resolve only at approval, never
/// mutate/create or default to deck 1 before the user approves.
@MainActor
final class AIReviewerAddCardTests: XCTestCase {

    private func makeReviewer(reply: String = "") throws -> (AIChatViewModel, StubCollectionGateway) {
        let db = try AIDatabase(path: ":memory:")
        let settings = AISettingsStore(keychain: InMemorySecretStore(),
                                       defaults: UserDefaults(suiteName: "rv-\(UUID().uuidString)")!)
        settings.apiKey = "sk-ant-test"
        let gateway = StubCollectionGateway()
        let fake = FakeChatClient(reply: .success(reply))
        let vm = AIChatViewModel(cardId: 5, gateway: gateway, db: db, settings: settings,
                                 clientFactory: { _, _ in fake })
        return (vm, gateway)
    }

    private func proposal(_ deck: String) -> AddCardProposal {
        AddCardProposal(front: "Q", back: "A", deckName: deck, explanation: "")
    }

    func testApprovalAddsToExistingDeck() async throws {
        let (vm, gateway) = try makeReviewer()
        await vm.approveAddCardProposal(proposal("Physics"))   // exists as id 2
        let added = await gateway.lastAddedDeckId
        XCTAssertEqual(added, 2)
        XCTAssertNil(vm.pendingAddCardProposal)
    }

    func testMissingDeckRequiresConfirmationWithoutMutation() async throws {
        let (vm, gateway) = try makeReviewer()
        let before = (try? await gateway.allDecks().count) ?? 0
        await vm.approveAddCardProposal(proposal("Brand New Deck"))
        XCTAssertNotNil(vm.pendingAddCardMissingDeck, "missing deck asks the user")
        let addedBefore = await gateway.lastAddedDeckId
        XCTAssertNil(addedBefore, "no card added before confirmation")
        let countBeforeConfirm = (try? await gateway.allDecks().count) ?? 0
        XCTAssertEqual(countBeforeConfirm, before, "no deck created before confirmation")

        await vm.confirmCreateMissingDeckAndAdd()
        let addedAfter = await gateway.lastAddedDeckId
        XCTAssertNotNil(addedAfter)
        XCTAssertNotEqual(addedAfter, 1, "created a new deck, not the Default deck")
        XCTAssertNil(vm.pendingAddCardMissingDeck)
    }

    func testNeverDefaultsToDeckId1OnMissingDeck() async throws {
        let (vm, gateway) = try makeReviewer()
        await vm.approveAddCardProposal(proposal("Ghost"))
        let added = await gateway.lastAddedDeckId
        XCTAssertNil(added, "did not silently add to deck id 1")
        XCTAssertNotNil(vm.pendingAddCardMissingDeck)
    }

    func testAlternativeExistingDeckSelection() async throws {
        let (vm, gateway) = try makeReviewer()
        await vm.approveAddCardProposal(proposal("Ghost"))     // missing → pending
        await vm.addProposalToExistingDeck(2)                  // user picks Physics
        let added = await gateway.lastAddedDeckId
        XCTAssertEqual(added, 2)
        XCTAssertNil(vm.pendingAddCardMissingDeck)
    }

    func testCancelLeavesCollectionUnmutated() async throws {
        let (vm, gateway) = try makeReviewer()
        await vm.approveAddCardProposal(proposal("Ghost"))
        vm.dismissMissingDeck()
        vm.dismissAddCardProposal()
        let added = await gateway.lastAddedDeckId
        XCTAssertNil(added, "cancelling adds nothing")
    }
}
