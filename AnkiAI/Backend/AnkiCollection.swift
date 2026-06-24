import Foundation
import AnkiCore

/// Errors surfaced from the Rust backend bridge.
enum AnkiBackendError: Error, CustomStringConvertible {
    case open(String)
    case deckTree(String)
    case render(String)
    case answer(String)
    case decode(String)
    case createFixture(String)

    var description: String {
        switch self {
        case .open(let m): return "open collection failed: \(m)"
        case .deckTree(let m): return "deck tree failed: \(m)"
        case .render(let m): return "render failed: \(m)"
        case .answer(let m): return "answer failed: \(m)"
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

    /// Answer/grade a card now via the scheduler (mutates the collection).
    func answerCard(cardId: Int64, rating: Int32) throws {
        let rc = anki_backend_answer_card(handle, cardId, rating)
        guard rc == 0 else { throw AnkiBackendError.answer(Self.lastError()) }
    }

    static func lastError() -> String {
        guard let c = anki_backend_last_error() else { return "unknown error" }
        return String(cString: c)
    }

    /// Test/seed support: create a deterministic sample collection at `path`
    /// (real backend writes — not hardcoded data). Used by integration tests and
    /// for first-launch seeding of the app's collection.
    static func createFixture(path: String) throws {
        let rc = path.withCString { anki_backend_create_fixture($0) }
        guard rc == 0 else { throw AnkiBackendError.createFixture(lastError()) }
    }
}
