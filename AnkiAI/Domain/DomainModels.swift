import Foundation

/// Lightweight domain value types mirroring the libanki Kotlin models the AI
/// layer interacts with. The authoritative implementations of these (with
/// scheduling/sync semantics) come from the Rust `anki` backend in milestone 2;
/// these structs are the Swift-side representation passed across the gateway.

public struct DeckNameId: Equatable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public init(id: Int64, name: String) { self.id = id; self.name = name }
}

public struct NoteData: Equatable, Sendable {
    public let id: Int64
    public let notetypeId: Int64
    public var fields: [String]
    public init(id: Int64, notetypeId: Int64, fields: [String]) {
        self.id = id; self.notetypeId = notetypeId; self.fields = fields
    }
}

public struct NotetypeNameId: Equatable, Sendable {
    public let id: Int64
    public let name: String
    public init(id: Int64, name: String) { self.id = id; self.name = name }
}

/// The minimal collection surface the AI features need. Implemented by:
///  - `StubCollectionGateway` (milestone 1, in-memory, lets the UI run on CI)
///  - `BackendCollectionGateway` (milestone 2, backed by the Rust anki backend)
public protocol CollectionGateway: AnyObject, Sendable {
    func allDecks() async throws -> [DeckNameId]
    func deckName(id: Int64) async throws -> String?
    /// Resolve an exact deck name to an id, creating it if necessary (mirrors `decks.id(name)`).
    func resolveOrCreateDeck(name: String) async throws -> Int64

    /// Load (noteId, deckId, fields) for a card id.
    func cardContext(cardId: Int64) async throws -> (noteId: Int64, deckId: Int64, fields: [String])?

    func note(id: Int64) async throws -> NoteData
    func updateNote(_ note: NoteData) async throws
    func basicNotetypeId() async throws -> Int64
    func addNote(notetypeId: Int64, fields: [String], deckId: Int64) async throws -> Int64
}

public enum GatewayError: Error { case notFound, noNotetypes }
