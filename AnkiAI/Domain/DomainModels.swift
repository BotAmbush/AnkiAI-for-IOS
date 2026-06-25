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
    /// When non-nil, replaces the note's tags on update; nil keeps existing tags.
    public var tags: [String]?
    public init(id: Int64, notetypeId: Int64, fields: [String], tags: [String]? = nil) {
        self.id = id; self.notetypeId = notetypeId; self.fields = fields; self.tags = tags
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

/// A note prepared for the manual editor (M2.15): field names + current values.
public struct EditableNote: Equatable, Sendable {
    public let noteId: Int64
    public let notetypeName: String
    public let fieldNames: [String]
    public var fields: [String]
    public var tags: [String]
    public init(noteId: Int64, notetypeName: String, fieldNames: [String], fields: [String], tags: [String] = []) {
        self.noteId = noteId
        self.notetypeName = notetypeName
        self.fieldNames = fieldNames
        self.fields = fields
        self.tags = tags
    }
}

/// Scheduling info for a card (M2.12). `dueDate` is set for review/learning
/// cards; `duePosition` is the new-queue position for new cards.
public struct CardInfo: Equatable, Sendable {
    public let noteId: Int64
    public let dueDate: Date?
    public let duePosition: Int?
    public let interval: Int      // days
    public let ease: Int          // per mille (e.g. 2500 = 250%)
    public let reviews: Int
    public let lapses: Int
    public let cardType: String
    public let deck: String
    public init(noteId: Int64, dueDate: Date?, duePosition: Int?, interval: Int, ease: Int,
                reviews: Int, lapses: Int, cardType: String, deck: String) {
        self.noteId = noteId
        self.dueDate = dueDate
        self.duePosition = duePosition
        self.interval = interval
        self.ease = ease
        self.reviews = reviews
        self.lapses = lapses
        self.cardType = cardType
        self.deck = deck
    }
}

/// The scheduler queue state for the current deck (M2.32): the next due card
/// (nil = nothing left to study now) + remaining new/learning/review counts.
public struct DueQueueState: Equatable, Sendable {
    public let cardId: Int64?
    public let newCount: Int
    public let learnCount: Int
    public let reviewCount: Int
    public init(cardId: Int64?, newCount: Int, learnCount: Int, reviewCount: Int) {
        self.cardId = cardId
        self.newCount = newCount
        self.learnCount = learnCount
        self.reviewCount = reviewCount
    }
}

/// Read-only deck scheduling options (M2.44). Editing is intentionally not exposed
/// (risky to write on a live synced collection); values come down with sync.
public struct DeckOptions: Equatable, Sendable {
    public let configName: String
    public let newPerDay: Int
    public let reviewsPerDay: Int
    public let desiredRetention: Double
    public let fsrs: Bool
    public init(configName: String, newPerDay: Int, reviewsPerDay: Int, desiredRetention: Double, fsrs: Bool) {
        self.configName = configName
        self.newPerDay = newPerDay
        self.reviewsPerDay = reviewsPerDay
        self.desiredRetention = desiredRetention
        self.fsrs = fsrs
    }
}

/// A single (dayOffset, count) point in a statistics graph (M2.33).
public struct GraphPoint: Equatable, Sendable, Identifiable {
    public let day: Int
    public let count: Int
    public var id: Int { day }
    public init(day: Int, count: Int) { self.day = day; self.count = count }
}

/// Backend statistics graph series. `reviews`/`added` use negative day offsets
/// (days ago); `futureDue` uses 0,1,2… (days ahead).
public struct StatsGraphs: Equatable, Sendable {
    public let reviews: [GraphPoint]
    public let futureDue: [GraphPoint]
    public let added: [GraphPoint]
    public init(reviews: [GraphPoint], futureDue: [GraphPoint], added: [GraphPoint]) {
        self.reviews = reviews
        self.futureDue = futureDue
        self.added = added
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
    /// Begin studying a deck's scheduler queue; then fetch the next DUE card +
    /// remaining counts (respects due/limits, excludes suspended) (M2.32).
    func setStudyDeck(named name: String) async throws
    func nextDueCard() async throws -> DueQueueState
    /// Card ids matching an arbitrary Anki search string (M2.7 card browser).
    func searchCardIds(query: String) async throws -> [Int64]
    /// Statistics graph series (reviews/future-due/added) for the collection (M2.33).
    func statsGraphs(search: String, days: Int) async throws -> StatsGraphs
    /// Read-only deck scheduling options (limits + desired retention) (M2.44).
    func deckOptions(deckId: Int64) async throws -> DeckOptions
    /// Backend-rendered question/answer HTML + CSS for a card (M2.2 read path).
    func renderCard(cardId: Int64) async throws -> RenderedCard
    /// Scheduling info (due/interval/reviews/…) for a card (M2.12).
    func cardInfo(cardId: Int64) async throws -> CardInfo
    /// Answer/grade a card via the real backend scheduler (M2.3 write path).
    func answerCard(cardId: Int64, rating: AnswerRating) async throws
    /// Interval labels for the answer buttons, [again, hard, good, easy] (M2.11).
    func answerButtonLabels(cardId: Int64) async throws -> [String]
    /// Suspend / bury a card; undo the last operation (M2.4 write paths).
    func suspendCard(cardId: Int64) async throws
    func unsuspendCard(cardId: Int64) async throws
    func buryCard(cardId: Int64) async throws
    func undo() async throws
    /// Reschedule a card's due date (Anki spec, e.g. "0","3","1-7") / forget it (M2.35).
    func setDueDate(cardId: Int64, spec: String) async throws
    func forgetCard(cardId: Int64) async throws
    /// Move a card to another deck (M2.6).
    func moveCard(cardId: Int64, toDeckId: Int64) async throws
    /// Rename / delete a deck (M2.17).
    func renameDeck(deckId: Int64, newName: String) async throws
    func removeDeck(deckId: Int64) async throws
    /// Create/rebuild a filtered deck (custom study) gathering cards by search (M2.25).
    func createFilteredDeck(name: String, search: String, limit: Int) async throws -> Int64
    /// Set a card flag (0=none,1=red,2=orange,3=green,4=blue) / add note tags (M2.9).
    func setFlag(cardId: Int64, flag: Int) async throws
    func addTags(noteId: Int64, tags: String) async throws
    /// Export the whole collection to / import an `.apkg` (M2.10).
    func exportApkg(toPath path: String) async throws
    func importApkg(fromPath path: String) async throws
    func allDecks() async throws -> [DeckNameId]
    func deckName(id: Int64) async throws -> String?
    /// Resolve an exact deck name to an id, creating it if necessary (mirrors `decks.id(name)`).
    func resolveOrCreateDeck(name: String) async throws -> Int64

    /// Load (noteId, deckId, fields) for a card id.
    func cardContext(cardId: Int64) async throws -> (noteId: Int64, deckId: Int64, fields: [String])?

    func note(id: Int64) async throws -> NoteData
    func updateNote(_ note: NoteData) async throws
    /// Load a card's note for the manual editor (field names + values) (M2.15).
    func editableNote(cardId: Int64) async throws -> EditableNote
    /// AnkiWeb: log in (returns hkey); full-download the collection (M2.19).
    func syncLogin(username: String, password: String) async throws -> String
    func downloadFromAnkiWeb(hkey: String) async throws
    /// Two-way sync (returns true if a full sync is required); full-upload (M2.20).
    func sync(hkey: String) async throws -> Bool
    func uploadToAnkiWeb(hkey: String) async throws
    /// Media files folder (`<col>.media`); sync media; back up to .colpkg (M2.24).
    nonisolated var mediaDirectory: URL? { get }
    func syncMedia(hkey: String) async throws
    func backup(toPath outPath: String) async throws
    /// Restore a .colpkg, replacing the whole collection (M2.27).
    func restore(fromColpkg colpkgPath: String) async throws
    func basicNotetypeId() async throws -> Int64
    /// Look up a notetype id by name (e.g. "Basic", "Cloze") (M2.16).
    func notetypeId(named name: String) async throws -> Int64
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
