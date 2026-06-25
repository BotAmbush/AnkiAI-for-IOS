import Foundation

/// Shared, app-wide dependencies.
///
/// M2.1: the production collection gateway is the real `BackendCollectionGateway`
/// (Rust backend) — `StubCollectionGateway` is no longer used in production
/// (only previews / isolated unit tests). On first launch a real sample
/// collection is seeded via the backend (real writes, not hardcoded data).
@MainActor
public final class AppEnvironment: ObservableObject {
    public let gateway: CollectionGateway
    public let database: AIDatabase
    public let settings: AISettingsStore
    public let collectionPath: String

    /// Deterministic collection-file path (also used by background sync).
    public static func defaultCollectionPath() -> String {
        let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return (support ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("collection.anki2").path
    }

    public init() {
        let colURL = URL(fileURLWithPath: AppEnvironment.defaultCollectionPath())
        self.collectionPath = colURL.path

        // First launch: seed a real sample collection through the backend.
        if !FileManager.default.fileExists(atPath: colURL.path) {
            try? AnkiCollection.createFixture(path: colURL.path)
        }
        self.gateway = BackendCollectionGateway(path: colURL.path)

        self.settings = AISettingsStore()
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
        try! AIDatabase(path: ":memory:")
    }
}
