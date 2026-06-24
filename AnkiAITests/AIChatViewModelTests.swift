import XCTest
@testable import AnkiAI

/// A scripted client returning a fixed reply, capturing the prompt it was given.
final class FakeChatClient: AIChatAPIClient, @unchecked Sendable {
    let reply: Result<String, AIClientError>
    private(set) var lastSystemPrompt: String?
    private(set) var lastHistory: [ChatTurn] = []
    private(set) var lastDynamicSuffix: String = ""

    init(reply: Result<String, AIClientError>) { self.reply = reply }

    func chat(systemPrompt: String, history: [ChatTurn], dynamicSystemSuffix: String,
              onTokensUsed: (@Sendable (TokenUsage) -> Void)?) async -> Result<String, AIClientError> {
        lastSystemPrompt = systemPrompt
        lastHistory = history
        lastDynamicSuffix = dynamicSystemSuffix
        onTokensUsed?(TokenUsage(inputTokens: 100, outputTokens: 50, cacheCreationTokens: 0, cacheReadTokens: 0))
        return reply
    }
}

@MainActor
final class AIChatViewModelTests: XCTestCase {

    private func makeVM(cardId: Int64, reply: Result<String, AIClientError>) throws -> (AIChatViewModel, FakeChatClient, AISettingsStore) {
        let db = try AIDatabase(path: ":memory:")
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AISettingsStore(keychain: InMemorySecretStore(), defaults: defaults)
        settings.apiKey = "sk-ant-test"
        let fake = FakeChatClient(reply: reply)
        let vm = AIChatViewModel(cardId: cardId, gateway: StubCollectionGateway(), db: db,
                                 settings: settings, clientFactory: { _, _ in fake })
        return (vm, fake, settings)
    }

    func testReviewerPlainReplyPersisted() async throws {
        let (vm, _, _) = try makeVM(cardId: 1000, reply: .success("Because energy is quantized."))
        await vm.load()
        await vm.sendMessage("Why?")
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages[0].role, AIChatMessage.roleUser)
        XCTAssertEqual(vm.messages[1].content, "Because energy is quantized.")
    }

    func testReviewerSystemPromptIncludesCardContext() async throws {
        let (vm, fake, _) = try makeVM(cardId: 1000, reply: .success("ok"))
        await vm.load()
        await vm.sendMessage("Explain")
        XCTAssertTrue(fake.lastSystemPrompt?.contains("CARD BEING REVIEWED") ?? false)
        XCTAssertTrue(fake.lastSystemPrompt?.contains("Physics::Quantum") ?? false)
    }

    func testEditProposalSurfaced() async throws {
        let reply = #"{"action":"edit_card","fieldName":"Front","newContent":"<b>better</b>","explanation":"clearer"}"#
        let (vm, _, _) = try makeVM(cardId: 1000, reply: .success(reply))
        await vm.load()
        await vm.sendMessage("improve this")
        XCTAssertNotNil(vm.pendingEditProposal)
        XCTAssertEqual(vm.pendingEditProposal?.fieldName, "Front")
        XCTAssertEqual(vm.pendingEditProposal?.newContent, "<b>better</b>")
    }

    func testApproveEditUpdatesNote() async throws {
        let reply = #"{"action":"edit_card","fieldName":"Front","newContent":"<b>NEW</b>","explanation":"x"}"#
        let gateway = StubCollectionGateway()
        let db = try AIDatabase(path: ":memory:")
        let settings = AISettingsStore(keychain: InMemorySecretStore(), defaults: UserDefaults(suiteName: "t-\(UUID())")!)
        settings.apiKey = "sk-ant-test"
        let fake = FakeChatClient(reply: .success(reply))
        let vm = AIChatViewModel(cardId: 1000, gateway: gateway, db: db, settings: settings,
                                 clientFactory: { _, _ in fake })
        await vm.load()
        await vm.sendMessage("improve")
        let proposal = try XCTUnwrap(vm.pendingEditProposal)
        await vm.approveEditProposal(proposal)
        let note = try await gateway.note(id: proposal.noteId)
        XCTAssertEqual(note.fields[0], "<b>NEW</b>")
        XCTAssertNil(vm.pendingEditProposal)
    }

    func testCreatorParsesProposals() async throws {
        let reply = #"[{"front":"Q1","back":"A1","deckName":"Physics"},{"front":"Q2","back":"A2","deckName":"Default"}]"#
        let (vm, fake, _) = try makeVM(cardId: -1, reply: .success(reply))
        await vm.load()
        await vm.generateCards("teach me physics")
        XCTAssertEqual(vm.generationProposals.count, 2)
        XCTAssertEqual(vm.generationProposals[0].front, "Q1")
        // Creator uses prompt caching → dynamic suffix carries the deck list.
        XCTAssertTrue(fake.lastDynamicSuffix.contains("AVAILABLE DECKS"))
    }

    func testSpendTracked() async throws {
        let (vm, _, _) = try makeVM(cardId: 1000, reply: .success("hi"))
        await vm.load()
        await vm.sendMessage("q")
        XCTAssertGreaterThan(vm.totalSpentUSD, 0)
    }

    func testErrorSurfacedOnFailure() async throws {
        let (vm, _, _) = try makeVM(cardId: 1000, reply: .failure(.unauthorized))
        await vm.load()
        await vm.sendMessage("q")
        XCTAssertEqual(vm.error, "Invalid API key. Check your key in Settings → AI Assistant.")
    }
}
