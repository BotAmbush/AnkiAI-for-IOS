import XCTest
@testable import AnkiAI

/// Repair 3 — creator attachment persistence/size failures are surfaced (not silent),
/// failed attachments are not kept/sent, and the count matches persisted files.
@MainActor
final class AICreatorAttachmentTests: XCTestCase {

    override func setUp() { CreatorSessionStore.clear(sessionId: "creator") }
    override func tearDown() { CreatorSessionStore.clear(sessionId: "creator") }

    private func makeCreator() throws -> AIChatViewModel {
        let db = try AIDatabase(path: ":memory:")
        let settings = AISettingsStore(keychain: InMemorySecretStore(),
                                       defaults: UserDefaults(suiteName: "ca-\(UUID().uuidString)")!)
        settings.apiKey = "sk-ant-test"
        return AIChatViewModel(cardId: -1, gateway: StubCollectionGateway(), db: db,
                               settings: settings, clientFactory: { _, _ in FakeChatClient(reply: .success("")) })
    }

    private func payload(_ n: Int) -> ImagePayload {
        ImagePayload(base64: Data(repeating: 0x41, count: n).base64EncodedString(), mediaType: "image/png")
    }

    func testOversizedAttachmentSurfacedAndNotKept() async throws {
        let vm = try makeCreator(); await vm.load()
        let ok = vm.attachFiles([payload(CreatorAttachmentStore.maxFileBytes + 1)])
        XCTAssertFalse(ok)
        XCTAssertTrue(vm.error?.localizedCaseInsensitiveContains("too large") ?? false, "shows the per-file limit")
        XCTAssertEqual(vm.attachmentCount, 0)
        XCTAssertTrue(vm.pendingAttachments.isEmpty, "a failed attachment is not kept or sent")
    }

    func testValidAttachmentKeptAndPersisted() async throws {
        let vm = try makeCreator(); await vm.load()
        XCTAssertTrue(vm.attachFiles([payload(1000)]))
        XCTAssertEqual(vm.attachmentCount, 1)
        XCTAssertEqual(vm.pendingAttachments.count, 1)
    }

    func testRetrySucceedsAfterFailure() async throws {
        let vm = try makeCreator(); await vm.load()
        _ = vm.attachFiles([payload(CreatorAttachmentStore.maxFileBytes + 1)])  // fails
        XCTAssertEqual(vm.attachmentCount, 0)
        XCTAssertTrue(vm.attachFiles([payload(500)]), "retry with a smaller file succeeds")
        XCTAssertEqual(vm.attachmentCount, 1)
    }

    func testAttachmentCountMatchesPersistedAfterRelaunch() async throws {
        let vm1 = try makeCreator(); await vm1.load()
        XCTAssertTrue(vm1.attachFiles([payload(800), payload(900)]))

        let vm2 = try makeCreator(); await vm2.load()
        XCTAssertEqual(vm2.attachmentCount, 2, "restored count matches persisted attachments")
        XCTAssertEqual(vm2.pendingAttachments.count, 2)
    }
}
