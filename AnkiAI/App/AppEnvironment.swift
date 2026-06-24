import Foundation

/// Shared, app-wide dependencies. Milestone 1 wires the in-memory stub gateway;
/// milestone 2 swaps in the Rust-backend-backed gateway without touching the UI.
@MainActor
public final class AppEnvironment: ObservableObject {
    public let gateway: CollectionGateway
    public let database: AIDatabase
    public let settings: AISettingsStore

    public init() {
        self.gateway = StubCollectionGateway()
        self.settings = AISettingsStore()
        // Fall back to in-memory if the support directory is unavailable.
        if let db = try? AIDatabase.makeDefault() {
            self.database = db
        } else {
            self.database = (try? AIDatabase(path: ":memory:")) ?? AppEnvironment.emptyMemoryDB()
        }
    }

    public func makeChatViewModel(cardId: Int64) -> AIChatViewModel {
        AIChatViewModel(cardId: cardId, gateway: gateway, db: database, settings: settings)
    }

    private static func emptyMemoryDB() -> AIDatabase {
        // Best-effort: a fresh in-memory DB. Force-unwrap is safe — opening
        // ":memory:" cannot fail on a functioning system.
        try! AIDatabase(path: ":memory:")
    }
}
