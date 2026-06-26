import Foundation

/// In-memory collection gateway for milestone 1 (UI + AI layer run end-to-end on
/// CI and Simulator without the Rust backend). Milestone 2 replaces this with a
/// backend-backed gateway that opens the real `collection.anki2`.
public actor StubCollectionGateway: CollectionGateway {
    private var decks: [DeckNameId]
    private var notes: [Int64: NoteData]
    private var cardToNoteDeck: [Int64: (noteId: Int64, deckId: Int64)]
    private var nextId: Int64 = 1_000_000
    private let basicNotetype = NotetypeNameId(id: 1, name: "Basic")

    public init() {
        decks = [
            DeckNameId(id: 1, name: "Default"),
            DeckNameId(id: 2, name: "Physics"),
            DeckNameId(id: 3, name: "Physics::Quantum"),
            DeckNameId(id: 4, name: "Hebrew Vocabulary"),
        ]
        let sampleNote = NoteData(
            id: 100, notetypeId: 1,
            fields: [
                #"<div dir="rtl" style="text-align: right;"><b>מהי קבוע פלאנק?</b></div>"#,
                #"<div dir="rtl" style="text-align: right; line-height: 1.7;">קבוע פלאנק <span dir="ltr">\(h \approx 6.626\times10^{-34}\)</span><span dir="ltr"> J·s</span></div>"#,
            ])
        notes = [100: sampleNote]
        cardToNoteDeck = [1000: (noteId: 100, deckId: 3)]
    }

    public func deckTree() async throws -> [DeckTreeEntry] {
        // Preview/test only: zero counts. Production uses BackendCollectionGateway.
        decks.map {
            DeckTreeEntry(deckId: $0.id, name: $0.name,
                          level: $0.name.components(separatedBy: "::").count - 1,
                          newCount: 0, learnCount: 0, reviewCount: 0)
        }
    }

    public func cardIds(inDeckNamed name: String) async throws -> [Int64] {
        // Preview/test only.
        cardToNoteDeck.keys.sorted()
    }

    public func searchCardIds(query: String) async throws -> [Int64] {
        cardToNoteDeck.keys.sorted()
    }
    public func statsGraphs(search: String, days: Int) async throws -> StatsGraphs {
        StatsGraphs(reviews: [], futureDue: [], added: [])
    }
    public func deckOptions(deckId: Int64) async throws -> DeckOptions {
        DeckOptions(configName: "Default", newPerDay: 20, reviewsPerDay: 200, desiredRetention: 0.9, fsrs: true)
    }
    public func setStudyDeck(named name: String) async throws {}
    public func nextDueCard() async throws -> DueQueueState {
        DueQueueState(cardId: cardToNoteDeck.keys.sorted().first, newCount: 1, learnCount: 0, reviewCount: 0)
    }

    public func renderCard(cardId: Int64) async throws -> RenderedCard {
        throw GatewayError.notImplementedInM21("renderCard")
    }
    public func cardInfo(cardId: Int64) async throws -> CardInfo {
        throw GatewayError.notImplementedInM21("cardInfo")
    }
    public func editableNote(cardId: Int64) async throws -> EditableNote {
        throw GatewayError.notImplementedInM21("editableNote")
    }
    public func syncLogin(username: String, password: String) async throws -> String {
        throw GatewayError.notImplementedInM21("syncLogin")
    }
    public func downloadFromAnkiWeb(hkey: String) async throws {
        throw GatewayError.notImplementedInM21("downloadFromAnkiWeb")
    }
    public func sync(hkey: String) async throws -> Bool { throw GatewayError.notImplementedInM21("sync") }
    public func uploadToAnkiWeb(hkey: String) async throws { throw GatewayError.notImplementedInM21("uploadToAnkiWeb") }
    public nonisolated var mediaDirectory: URL? { nil }
    public func syncMedia(hkey: String) async throws { throw GatewayError.notImplementedInM21("syncMedia") }
    public func backup(toPath outPath: String) async throws { throw GatewayError.notImplementedInM21("backup") }
    public func restore(fromColpkg colpkgPath: String) async throws { throw GatewayError.notImplementedInM21("restore") }

    public func answerCard(cardId: Int64, rating: AnswerRating) async throws {
        throw GatewayError.notImplementedInM21("answerCard")
    }
    public func answerButtonLabels(cardId: Int64) async throws -> [String] {
        ["", "", "", ""]
    }

    public func suspendCard(cardId: Int64) async throws { throw GatewayError.notImplementedInM21("suspendCard") }
    public func unsuspendCard(cardId: Int64) async throws { throw GatewayError.notImplementedInM21("unsuspendCard") }
    public func buryCard(cardId: Int64) async throws { throw GatewayError.notImplementedInM21("buryCard") }
    public func undo() async throws { throw GatewayError.notImplementedInM21("undo") }
    public func setDueDate(cardId: Int64, spec: String) async throws { throw GatewayError.notImplementedInM21("setDueDate") }
    public func forgetCard(cardId: Int64) async throws { throw GatewayError.notImplementedInM21("forgetCard") }
    public func moveCard(cardId: Int64, toDeckId: Int64) async throws { throw GatewayError.notImplementedInM21("moveCard") }
    public func renameDeck(deckId: Int64, newName: String) async throws { throw GatewayError.notImplementedInM21("renameDeck") }
    public func removeDeck(deckId: Int64) async throws { throw GatewayError.notImplementedInM21("removeDeck") }
    public func createFilteredDeck(name: String, search: String, limit: Int) async throws -> Int64 { throw GatewayError.notImplementedInM21("createFilteredDeck") }
    public func setFlag(cardId: Int64, flag: Int) async throws { throw GatewayError.notImplementedInM21("setFlag") }
    public func addTags(noteId: Int64, tags: String) async throws { throw GatewayError.notImplementedInM21("addTags") }
    public func exportApkg(toPath path: String) async throws { throw GatewayError.notImplementedInM21("exportApkg") }
    public func importApkg(fromPath path: String) async throws { throw GatewayError.notImplementedInM21("importApkg") }

    public func allDecks() async throws -> [DeckNameId] { decks }

    public func deckName(id: Int64) async throws -> String? { decks.first { $0.id == id }?.name }

    public func resolveOrCreateDeck(name: String) async throws -> Int64 {
        if let existing = decks.first(where: { $0.name == name }) { return existing.id }
        nextId += 1
        let deck = DeckNameId(id: nextId, name: name)
        decks.append(deck)
        return deck.id
    }

    public func cardContext(cardId: Int64) async throws -> (noteId: Int64, deckId: Int64, fields: [String])? {
        guard let link = cardToNoteDeck[cardId], let note = notes[link.noteId] else { return nil }
        return (noteId: link.noteId, deckId: link.deckId, fields: note.fields)
    }

    public func note(id: Int64) async throws -> NoteData {
        guard let note = notes[id] else { throw GatewayError.notFound }
        return note
    }

    public func updateNote(_ note: NoteData) async throws { notes[note.id] = note }

    public func basicNotetypeId() async throws -> Int64 { basicNotetype.id }
    public func notetypeId(named name: String) async throws -> Int64 { basicNotetype.id }

    public private(set) var lastAddedDeckId: Int64?

    public func addNote(notetypeId: Int64, fields: [String], deckId: Int64) async throws -> Int64 {
        nextId += 1
        notes[nextId] = NoteData(id: nextId, notetypeId: notetypeId, fields: fields)
        lastAddedDeckId = deckId
        return nextId
    }
}
