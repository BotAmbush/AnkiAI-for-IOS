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

    public func cardIds(inDeckNamed name: String) async throws -> [Int64] {
        try opened().cardIds(inDeckNamed: name)
    }

    public func searchCardIds(query: String) async throws -> [Int64] {
        try opened().searchCardIds(query: query)
    }

    public func renderCard(cardId: Int64) async throws -> RenderedCard {
        try opened().renderCard(cardId: cardId)
    }
    public func cardInfo(cardId: Int64) async throws -> CardInfo {
        try opened().cardInfo(cardId: cardId)
    }

    public func answerCard(cardId: Int64, rating: AnswerRating) async throws {
        try opened().answerCard(cardId: cardId, rating: Int32(rating.rawValue))
    }
    public func answerButtonLabels(cardId: Int64) async throws -> [String] {
        try opened().answerButtonLabels(cardId: cardId)
    }

    public func suspendCard(cardId: Int64) async throws { try opened().suspendCard(cardId: cardId) }
    public func buryCard(cardId: Int64) async throws { try opened().buryCard(cardId: cardId) }
    public func undo() async throws { try opened().undo() }
    public func moveCard(cardId: Int64, toDeckId: Int64) async throws {
        try opened().setCardDeck(cardId: cardId, deckId: toDeckId)
    }
    public func setFlag(cardId: Int64, flag: Int) async throws {
        try opened().setFlag(cardId: cardId, flag: UInt32(max(0, flag)))
    }
    public func addTags(noteId: Int64, tags: String) async throws {
        try opened().addTags(noteId: noteId, tags: tags)
    }
    public func exportApkg(toPath path: String) async throws {
        try opened().exportApkg(toPath: path)
    }
    public func importApkg(fromPath path: String) async throws {
        try opened().importApkg(fromPath: path)
    }

    // MARK: - Note write path (M2.5: add-card wired; edit/cardContext later)

    public func resolveOrCreateDeck(name: String) async throws -> Int64 {
        try opened().resolveOrCreateDeck(name: name)
    }
    public func basicNotetypeId() async throws -> Int64 {
        try opened().basicNotetypeId()
    }
    public func addNote(notetypeId: Int64, fields: [String], deckId: Int64) async throws -> Int64 {
        try opened().addNote(notetypeId: notetypeId, fields: fields, deckId: deckId)
    }

    /// Card context for the "Ask Claude" reviewer chat — REAL raw note fields via
    /// the NotesService (card → note id via card_stats → get_note). This also
    /// gives the correct noteId so AI edit-card proposals target the real note.
    public func cardContext(cardId: Int64) async throws -> (noteId: Int64, deckId: Int64, fields: [String])? {
        let col = try opened()
        let info = try col.cardInfo(cardId: cardId)
        let noteData = try col.note(id: info.noteId)
        let deckId = (try? col.deckTree().first { $0.name == info.deck })?.deckId ?? 0
        return (noteId: info.noteId, deckId: deckId, fields: noteData.fields)
    }
    public func note(id: Int64) async throws -> NoteData {
        try opened().note(id: id)
    }
    public func updateNote(_ note: NoteData) async throws {
        try opened().updateNote(note)
    }
}
