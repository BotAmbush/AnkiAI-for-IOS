# Database & Data Model

## Two databases — kept strictly separate (mirrors the fork)

### 1. Anki collection — `collection.anki2` (owned by the Rust backend, M2)
Standard Anki SQLite schema (`col`, `notes`, `cards`, `revlog`, `decks`/`deck_config`,
`notetypes`/`templates`/`fields`, `graves`, media DB). The Swift app **never** opens this
directly — all access is through the backend, guaranteeing format + sync compatibility
(DL-001). The fork does not modify this schema; neither do we.

Columns the AI features read (read-only, via `RevlogAnalyzer` → gateway at M2):
`revlog(id, cid, ease, ivl, factor, time)`, `cards(id, nid, did, queue, ivl, factor, lapses)`,
`notes(id, flds)` with fields joined by the `\x1f` unit separator.

### 2. AI database — `ai_insights.db` (owned by `AIDatabase`, Swift)
Separate file, only `ai_*` tables. Android uses Room; iOS uses a thin wrapper over the
system `libsqlite3` (`SQLiteDatabase`) — no external dependency, so CI cannot break on
package resolution.

| Table | Source entity | iOS status |
|---|---|---|
| `ai_chat_messages` | `AiChatMessage` | ✅ implemented + tested (`id, sessionId, role, content, messageType, metadata, timestamp`) |
| `ai_card_meta` | `AiCardMeta` | ☐ M2 (needs revlog reads) |
| `ai_study_log` | `AiStudyLog` | ☐ M2 |

Session id convention (ported): `"creator"` for the creator, `"card_<id>"` for reviewer chats.

## Swift domain value types
`DeckNameId`, `NoteData`, `NotetypeNameId`, `CardChatContext`, `EditProposal`,
`AddCardProposal`, `CardProposal`, `AIChatMessage`, `InsightStats`, `DeckRetention`.
These cross the `CollectionGateway` seam; authoritative storage is the backend (M2).

## Migrations
- AI db: `CREATE TABLE IF NOT EXISTS` + indices in `AIDatabase.migrate()`. Android used
  destructive fallback (the data is non-authoritative cache). iOS will add versioned
  migrations as `ai_card_meta`/`ai_study_log` land.
- Collection migrations: handled entirely by the Rust backend (M2).

## Test coverage
`AIDatabaseTests` — insert/fetch ordering, session delete, metadata/type round-trip (in-memory).
