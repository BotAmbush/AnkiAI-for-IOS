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
    public func setStudyDeck(named name: String) async throws {
        let col = try opened()
        let deckId = try col.deckTree().first { $0.name == name }?.deckId
            ?? col.resolveOrCreateDeck(name: name)
        try col.setCurrentDeck(deckId: deckId)
    }
    public func nextDueCard() async throws -> DueQueueState {
        try opened().nextDueCard()
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
    public func renameDeck(deckId: Int64, newName: String) async throws {
        try opened().renameDeck(deckId: deckId, newName: newName)
    }
    public func removeDeck(deckId: Int64) async throws {
        try opened().removeDeck(deckId: deckId)
    }
    public func createFilteredDeck(name: String, search: String, limit: Int) async throws -> Int64 {
        try opened().createFilteredDeck(name: name, search: search, limit: limit)
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
    public func notetypeId(named name: String) async throws -> Int64 {
        try opened().notetypeId(named: name)
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
    public func editableNote(cardId: Int64) async throws -> EditableNote {
        let col = try opened()
        let info = try col.cardInfo(cardId: cardId)
        return try col.editableNote(noteId: info.noteId)
    }

    // MARK: - AnkiWeb sync (M2.19)

    public func syncLogin(username: String, password: String) async throws -> String {
        try AnkiCollection.syncLogin(username: username, password: password)
    }

    /// Replace the local collection with the AnkiWeb one (full download). Closes
    /// the open handle first so the file is free, then reopens lazily.
    public func downloadFromAnkiWeb(hkey: String) async throws {
        collection = nil  // release the open handle (deinit closes it)
        try AnkiCollection.syncDownload(path: path, hkey: hkey)
        _ = try opened()  // reopen the replaced collection
    }

    /// Two-way normal sync. Returns true if a full sync is required.
    public func sync(hkey: String) async throws -> Bool {
        collection = nil
        let fullRequired = try AnkiCollection.sync(path: path, hkey: hkey)
        _ = try opened()
        return fullRequired
    }

    public func uploadToAnkiWeb(hkey: String) async throws {
        collection = nil
        try AnkiCollection.syncUpload(path: path, hkey: hkey)
        _ = try opened()
    }

    /// The media folder for this collection (`<col>.media`), where image/audio
    /// files live — used by the WebView to resolve `<img>`/`[sound:]` references.
    public nonisolated var mediaDirectory: URL? {
        URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("media")
    }

    public func syncMedia(hkey: String) async throws {
        collection = nil
        try AnkiCollection.syncMedia(path: path, hkey: hkey)
        _ = try opened()
    }

    public func backup(toPath outPath: String) async throws {
        collection = nil
        try AnkiCollection.exportColpkg(path: path, outPath: outPath)
        _ = try opened()
    }

    public func restore(fromColpkg colpkgPath: String) async throws {
        collection = nil
        try AnkiCollection.importColpkg(path: path, colpkgPath: colpkgPath)
        _ = try opened()
    }
}
