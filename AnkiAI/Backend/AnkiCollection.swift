import Foundation
import AnkiCore

/// Errors surfaced from the Rust backend bridge.
enum AnkiBackendError: Error, CustomStringConvertible {
    case open(String)
    case deckTree(String)
    case render(String)
    case answer(String)
    case sync(String)
    case decode(String)
    case createFixture(String)

    var description: String {
        switch self {
        case .open(let m): return "open collection failed: \(m)"
        case .deckTree(let m): return "deck tree failed: \(m)"
        case .render(let m): return "render failed: \(m)"
        case .answer(let m): return "answer failed: \(m)"
        case .sync(let m): return "sync failed: \(m)"
        case .decode(let m): return "decode failed: \(m)"
        case .createFixture(let m): return "create fixture failed: \(m)"
        }
    }
}

/// Thin Swift owner of an opaque collection handle from `AnkiCore` (the Rust
/// backend xcframework). Explicit ownership: the handle is opened in `init` and
/// closed exactly once (in `close()`/`deinit`). No raw pointer escapes this type.
final class AnkiCollection {
    private var handle: OpaquePointer?

    /// DTO matching the backend's deck-tree JSON.
    private struct DeckDTO: Decodable {
        let deck_id: Int64
        let name: String
        let level: Int
        let new: Int
        let learn: Int
        let review: Int
    }

    init(path: String) throws {
        var out: OpaquePointer?
        let rc = path.withCString { anki_backend_open($0, &out) }
        guard rc == 0, let opened = out else {
            throw AnkiBackendError.open(Self.lastError())
        }
        handle = opened
    }

    deinit { close() }

    func close() {
        if let h = handle {
            _ = anki_backend_close(h)
            handle = nil
        }
    }

    /// Real deck tree with live new/learn/review counts.
    func deckTree() throws -> [DeckTreeEntry] {
        var out: UnsafeMutablePointer<CChar>?
        let rc = anki_backend_deck_tree_json(handle, &out)
        guard rc == 0, let cstr = out else {
            throw AnkiBackendError.deckTree(Self.lastError())
        }
        defer { anki_backend_string_free(cstr) }
        let data = Data(String(cString: cstr).utf8)
        do {
            let dtos = try JSONDecoder().decode([DeckDTO].self, from: data)
            return dtos.map {
                DeckTreeEntry(deckId: $0.deck_id, name: $0.name, level: $0.level,
                              newCount: $0.new, learnCount: $0.learn, reviewCount: $0.review)
            }
        } catch {
            throw AnkiBackendError.decode("\(error)")
        }
    }

    /// Card ids in a deck (and subdecks) by full deck name.
    func cardIds(inDeckNamed name: String) throws -> [Int64] {
        var out: UnsafeMutablePointer<CChar>?
        let rc = name.withCString { anki_backend_deck_card_ids(handle, $0, &out) }
        guard rc == 0, let cstr = out else { throw AnkiBackendError.deckTree(Self.lastError()) }
        defer { anki_backend_string_free(cstr) }
        let data = Data(String(cString: cstr).utf8)
        do { return try JSONDecoder().decode([Int64].self, from: data) }
        catch { throw AnkiBackendError.decode("\(error)") }
    }

    /// Card ids matching an arbitrary Anki search string (empty = all).
    func searchCardIds(query: String) throws -> [Int64] {
        var out: UnsafeMutablePointer<CChar>?
        let rc = query.withCString { anki_backend_search_card_ids(handle, $0, &out) }
        guard rc == 0, let cstr = out else { throw AnkiBackendError.deckTree(Self.lastError()) }
        defer { anki_backend_string_free(cstr) }
        let data = Data(String(cString: cstr).utf8)
        do { return try JSONDecoder().decode([Int64].self, from: data) }
        catch { throw AnkiBackendError.decode("\(error)") }
    }

    /// Backend-rendered question/answer HTML + CSS for a card.
    func renderCard(cardId: Int64) throws -> RenderedCard {
        var out: UnsafeMutablePointer<CChar>?
        let rc = anki_backend_render_card(handle, cardId, &out)
        guard rc == 0, let cstr = out else { throw AnkiBackendError.render(Self.lastError()) }
        defer { anki_backend_string_free(cstr) }
        let data = Data(String(cString: cstr).utf8)
        do {
            let dto = try JSONDecoder().decode(RenderDTO.self, from: data)
            return RenderedCard(questionHTML: dto.question_html, answerHTML: dto.answer_html, css: dto.css)
        } catch {
            throw AnkiBackendError.decode("\(error)")
        }
    }

    private struct RenderDTO: Decodable {
        let question_html: String
        let answer_html: String
        let css: String
    }

    private struct CardInfoDTO: Decodable {
        let note_id: Int64
        let due_date: Int64?
        let due_position: Int?
        let interval: Int
        let ease: Int
        let reviews: Int
        let lapses: Int
        let card_type: String
        let deck: String
    }

    func cardInfo(cardId: Int64) throws -> CardInfo {
        var out: UnsafeMutablePointer<CChar>?
        let rc = anki_backend_card_info(handle, cardId, &out)
        guard rc == 0, let cstr = out else { throw AnkiBackendError.render(Self.lastError()) }
        defer { anki_backend_string_free(cstr) }
        let data = Data(String(cString: cstr).utf8)
        do {
            let d = try JSONDecoder().decode(CardInfoDTO.self, from: data)
            return CardInfo(
                noteId: d.note_id,
                dueDate: d.due_date.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                duePosition: d.due_position,
                interval: d.interval, ease: d.ease, reviews: d.reviews, lapses: d.lapses,
                cardType: d.card_type, deck: d.deck)
        } catch {
            throw AnkiBackendError.decode("\(error)")
        }
    }

    private struct NoteFieldsDTO: Decodable {
        let notetype_id: Int64
        let notetype_name: String
        let fields: [String]
        let field_names: [String]
        let tags: [String]
    }

    private func noteFieldsDTO(noteId: Int64) throws -> NoteFieldsDTO {
        var out: UnsafeMutablePointer<CChar>?
        let rc = anki_backend_note_fields(handle, noteId, &out)
        guard rc == 0, let cstr = out else { throw AnkiBackendError.answer(Self.lastError()) }
        defer { anki_backend_string_free(cstr) }
        let data = Data(String(cString: cstr).utf8)
        do { return try JSONDecoder().decode(NoteFieldsDTO.self, from: data) }
        catch { throw AnkiBackendError.decode("\(error)") }
    }

    /// Raw note fields + notetype id (for editing existing notes).
    func note(id: Int64) throws -> NoteData {
        let d = try noteFieldsDTO(noteId: id)
        return NoteData(id: id, notetypeId: d.notetype_id, fields: d.fields)
    }

    /// A note prepared for the manual editor: field names + values.
    func editableNote(noteId: Int64) throws -> EditableNote {
        let d = try noteFieldsDTO(noteId: noteId)
        return EditableNote(noteId: noteId, notetypeName: d.notetype_name,
                            fieldNames: d.field_names, fields: d.fields)
    }

    func updateNote(_ note: NoteData) throws {
        let fieldsJSON = String(data: try JSONEncoder().encode(note.fields), encoding: .utf8) ?? "[]"
        let rc = fieldsJSON.withCString { anki_backend_update_note(handle, note.id, $0) }
        guard rc == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    /// Answer/grade a card now via the scheduler (mutates the collection).
    func answerCard(cardId: Int64, rating: Int32) throws {
        let rc = anki_backend_answer_card(handle, cardId, rating)
        guard rc == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    /// [again, hard, good, easy] interval labels for the answer buttons.
    func answerButtonLabels(cardId: Int64) throws -> [String] {
        var out: UnsafeMutablePointer<CChar>?
        let rc = anki_backend_answer_button_labels(handle, cardId, &out)
        guard rc == 0, let cstr = out else { throw AnkiBackendError.answer(Self.lastError()) }
        defer { anki_backend_string_free(cstr) }
        let data = Data(String(cString: cstr).utf8)
        do { return try JSONDecoder().decode([String].self, from: data) }
        catch { throw AnkiBackendError.decode("\(error)") }
    }

    func suspendCard(cardId: Int64) throws {
        guard anki_backend_suspend_card(handle, cardId) == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    func buryCard(cardId: Int64) throws {
        guard anki_backend_bury_card(handle, cardId) == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    func undo() throws {
        guard anki_backend_undo(handle) == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    func setCardDeck(cardId: Int64, deckId: Int64) throws {
        guard anki_backend_set_card_deck(handle, cardId, deckId) == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    func renameDeck(deckId: Int64, newName: String) throws {
        let rc = newName.withCString { anki_backend_rename_deck(handle, deckId, $0) }
        guard rc == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    func removeDeck(deckId: Int64) throws {
        guard anki_backend_remove_deck(handle, deckId) == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    func createFilteredDeck(name: String, search: String, limit: Int) throws -> Int64 {
        var out: Int64 = 0
        let rc = name.withCString { n in
            search.withCString { s in
                anki_backend_create_filtered_deck(handle, n, s, UInt32(max(0, limit)), &out)
            }
        }
        guard rc == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
        return out
    }

    func setFlag(cardId: Int64, flag: UInt32) throws {
        guard anki_backend_set_card_flag(handle, cardId, flag) == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    func addTags(noteId: Int64, tags: String) throws {
        let rc = tags.withCString { anki_backend_add_tags_to_note(handle, noteId, $0) }
        guard rc == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    func exportApkg(toPath path: String) throws {
        let rc = path.withCString { anki_backend_export_apkg(handle, $0) }
        guard rc == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    func importApkg(fromPath path: String) throws {
        let rc = path.withCString { anki_backend_import_apkg(handle, $0) }
        guard rc == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    func basicNotetypeId() throws -> Int64 {
        var out: Int64 = 0
        guard anki_backend_basic_notetype_id(handle, &out) == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
        return out
    }

    func notetypeId(named name: String) throws -> Int64 {
        var out: Int64 = 0
        let rc = name.withCString { anki_backend_notetype_id_by_name(handle, $0, &out) }
        guard rc == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
        return out
    }

    func resolveOrCreateDeck(name: String) throws -> Int64 {
        var out: Int64 = 0
        let rc = name.withCString { anki_backend_resolve_or_create_deck(handle, $0, &out) }
        guard rc == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
        return out
    }

    func addNote(notetypeId: Int64, fields: [String], deckId: Int64) throws -> Int64 {
        let fieldsJSON = String(data: try JSONEncoder().encode(fields), encoding: .utf8) ?? "[]"
        var out: Int64 = 0
        let rc = fieldsJSON.withCString { anki_backend_add_note(handle, notetypeId, deckId, $0, &out) }
        guard rc == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
        return out
    }

    static func lastError() -> String {
        guard let c = anki_backend_last_error() else { return "unknown error" }
        return String(cString: c)
    }

    /// AnkiWeb: log in, returning the session host key (hkey). Standalone (no handle).
    static func syncLogin(username: String, password: String) throws -> String {
        var out: UnsafeMutablePointer<CChar>?
        let rc = username.withCString { u in
            password.withCString { p in anki_backend_sync_login(u, p, &out) }
        }
        guard rc == 0, let cstr = out else { throw AnkiBackendError.sync(lastError()) }
        defer { anki_backend_string_free(cstr) }
        return String(cString: cstr)
    }

    /// AnkiWeb: full-download the collection for `hkey`, REPLACING the file at `path`.
    /// The caller must ensure no handle is open on `path` during this call.
    static func syncDownload(path: String, hkey: String) throws {
        let rc = path.withCString { p in
            hkey.withCString { h in anki_backend_sync_download(p, h) }
        }
        guard rc == 0 else { throw AnkiBackendError.sync(lastError()) }
    }

    /// AnkiWeb: two-way normal sync. Returns true if a full sync is required
    /// (caller must then download or upload). No handle may be open on `path`.
    static func sync(path: String, hkey: String) throws -> Bool {
        var required: Int32 = 0
        let rc = path.withCString { p in
            hkey.withCString { h in anki_backend_sync(p, h, &required) }
        }
        guard rc == 0 else { throw AnkiBackendError.sync(lastError()) }
        return required == 2
    }

    /// AnkiWeb: full-upload the local collection, REPLACING the remote.
    static func syncUpload(path: String, hkey: String) throws {
        let rc = path.withCString { p in
            hkey.withCString { h in anki_backend_sync_upload(p, h) }
        }
        guard rc == 0 else { throw AnkiBackendError.sync(lastError()) }
    }

    /// AnkiWeb: sync the media files (images/audio). No handle may be open on `path`.
    static func syncMedia(path: String, hkey: String) throws {
        let rc = path.withCString { p in
            hkey.withCString { h in anki_backend_sync_media(p, h) }
        }
        guard rc == 0 else { throw AnkiBackendError.sync(lastError()) }
    }

    /// Back up the whole collection (with media) to a `.colpkg`. No open handle.
    static func exportColpkg(path: String, outPath: String) throws {
        let rc = path.withCString { p in
            outPath.withCString { o in anki_backend_export_colpkg(p, o) }
        }
        guard rc == 0 else { throw AnkiBackendError.answer(lastError()) }
    }

    /// Test/seed support: create a deterministic sample collection at `path`
    /// (real backend writes — not hardcoded data). Used by integration tests and
    /// for first-launch seeding of the app's collection.
    static func createFixture(path: String) throws {
        let rc = path.withCString { anki_backend_create_fixture($0) }
        guard rc == 0 else { throw AnkiBackendError.createFixture(lastError()) }
    }
}
