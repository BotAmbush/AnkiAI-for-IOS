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

/// A deck with its live due counts, as returned by the real backend's deck tree.
/// `name` is the full "Parent::Child" name; `level` is the depth (0 = top level).
public struct DeckTreeEntry: Equatable, Identifiable, Sendable {
    public let deckId: Int64
    public let name: String
    public let level: Int
    public let newCount: Int
    public let learnCount: Int
    public let reviewCount: Int
    public var id: Int64 { deckId }
    public init(deckId: Int64, name: String, level: Int,
                newCount: Int, learnCount: Int, reviewCount: Int) {
        self.deckId = deckId
        self.name = name
        self.level = level
        self.newCount = newCount
        self.learnCount = learnCount
        self.reviewCount = reviewCount
    }
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

/// Answer rating for a reviewed card. Raw values match the backend (1..=4).
public enum AnswerRating: Int, Sendable, CaseIterable {
    case again = 1, hard = 2, good = 3, easy = 4
    public var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

/// A card rendered by the backend (templates + CSS), ready for the WebView.
public struct RenderedCard: Equatable, Sendable {
    public let questionHTML: String
    public let answerHTML: String
    public let css: String
    public init(questionHTML: String, answerHTML: String, css: String) {
        self.questionHTML = questionHTML
        self.answerHTML = answerHTML
        self.css = css
    }
}

/// The minimal collection surface the AI features need. Implemented by:
///  - `StubCollectionGateway` (milestone 1, in-memory, lets the UI run on CI)
///  - `BackendCollectionGateway` (milestone 2, backed by the Rust anki backend)
public protocol CollectionGateway: AnyObject, Sendable {
    /// Real deck tree with live new/learn/review counts (M2.1 read path).
    func deckTree() async throws -> [DeckTreeEntry]
    /// Card ids in a deck (and its subdecks), by full deck name (M2.2 read path).
    func cardIds(inDeckNamed name: String) async throws -> [Int64]
    /// Card ids matching an arbitrary Anki search string (M2.7 card browser).
    func searchCardIds(query: String) async throws -> [Int64]
    /// Backend-rendered question/answer HTML + CSS for a card (M2.2 read path).
    func renderCard(cardId: Int64) async throws -> RenderedCard
    /// Answer/grade a card via the real backend scheduler (M2.3 write path).
    func answerCard(cardId: Int64, rating: AnswerRating) async throws
    /// Suspend / bury a card; undo the last operation (M2.4 write paths).
    func suspendCard(cardId: Int64) async throws
    func buryCard(cardId: Int64) async throws
    func undo() async throws
    /// Move a card to another deck (M2.6).
    func moveCard(cardId: Int64, toDeckId: Int64) async throws
    /// Set a card flag (0=none,1=red,2=orange,3=green,4=blue) / add note tags (M2.9).
    func setFlag(cardId: Int64, flag: Int) async throws
    func addTags(noteId: Int64, tags: String) async throws
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

/// Collection-wide card statistics (M2.8). Computed from backend searches.
public struct CollectionStats: Equatable, Sendable {
    public let total: Int
    public let newCount: Int
    public let learning: Int
    public let review: Int
    public let suspended: Int
    public let mature: Int
    public init(total: Int, newCount: Int, learning: Int, review: Int, suspended: Int, mature: Int) {
        self.total = total
        self.newCount = newCount
        self.learning = learning
        self.review = review
        self.suspended = suspended
        self.mature = mature
    }
}

public extension CollectionGateway {
    /// Collection statistics computed via backend search queries. Default
    /// implementation works for any gateway that implements `searchCardIds`.
    func collectionStats() async throws -> CollectionStats {
        let total = try await searchCardIds(query: "").count
        let newCount = try await searchCardIds(query: "is:new").count
        let learning = try await searchCardIds(query: "is:learn").count
        let review = try await searchCardIds(query: "is:review").count
        let suspended = try await searchCardIds(query: "is:suspended").count
        let mature = try await searchCardIds(query: "prop:ivl>=21").count
        return CollectionStats(total: total, newCount: newCount, learning: learning,
                               review: review, suspended: suspended, mature: mature)
    }
}

public enum GatewayError: Error, Equatable {
    case notFound
    case noNotetypes
    /// A write/edit path not yet wired to the backend in milestone M2.1.
    case notImplementedInM21(String)
}
