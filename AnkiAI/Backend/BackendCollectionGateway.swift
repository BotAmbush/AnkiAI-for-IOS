import Foundation

/// Production `CollectionGateway` backed by the real Anki Rust backend.
///
/// M2.1 scope: the **read path** (deck tree with live counts, deck names) is
/// implemented against the backend. Write/edit paths (note add/update, card
/// context, notetypes) are intentionally NOT wired yet and throw
/// `GatewayError.notImplementedInM21` so callers fail loudly rather than
/// silently using stub data. They arrive in later milestones.
///
/// An `actor` serializes access to the non-thread-safe collection handle.
public actor BackendCollectionGateway: CollectionGateway {
    private let path: String
    private var collection: AnkiCollection?

    public init(path: String) {
        self.path = path
    }

    private func opened() throws -> AnkiCollection {
        if let c = collection { return c }
        let c = try AnkiCollection(path: path)
        collection = c
        return c
    }

    // MARK: - Read path (real)

    public func deckTree() async throws -> [DeckTreeEntry] {
        try opened().deckTree()
    }

    public func allDecks() async throws -> [DeckNameId] {
        try opened().deckTree().map { DeckNameId(id: $0.deckId, name: $0.name) }
    }

    public func deckName(id: Int64) async throws -> String? {
        try opened().deckTree().first { $0.deckId == id }?.name
    }

    // MARK: - Write/edit path (not in M2.1)

    public func resolveOrCreateDeck(name: String) async throws -> Int64 {
        throw GatewayError.notImplementedInM21("resolveOrCreateDeck")
    }
    public func cardContext(cardId: Int64) async throws -> (noteId: Int64, deckId: Int64, fields: [String])? {
        throw GatewayError.notImplementedInM21("cardContext")
    }
    public func note(id: Int64) async throws -> NoteData {
        throw GatewayError.notImplementedInM21("note")
    }
    public func updateNote(_ note: NoteData) async throws {
        throw GatewayError.notImplementedInM21("updateNote")
    }
    public func basicNotetypeId() async throws -> Int64 {
        throw GatewayError.notImplementedInM21("basicNotetypeId")
    }
    public func addNote(notetypeId: Int64, fields: [String], deckId: Int64) async throws -> Int64 {
        throw GatewayError.notImplementedInM21("addNote")
    }
}
