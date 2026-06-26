# Feature Parity Checklist

> **AUTHORITATIVE STATUS (reconciled 2026-06-26):** `docs/android-ios-feature-map.yml`
> is the single source of truth — **44 completed / 2 partial (AI Insights, forced
> study) / 9 physical-device-verified**, project in **initial-full-migration (Mode A),
> NOT finalized**. The per-row table below is an EARLY-MILESTONE (M1/M2) historical
> log; where a row marks ☐/🔬 for a feature the feature map lists as completed (cloze,
> media, card browser, editing, answer buttons, notes CRUD, review queue, import/
> export, sync), the feature map governs. Rows updated below for the worst conflicts.

Legend: ✅ complete · ◑ partial · ☐ not started · 🔬 needs Rust backend (M2)

A feature is **not** marked complete just because a similarly-named Swift file exists
(per CLAUDE.md). "Complete" means implemented **and** tested or rendered end-to-end.

## Core Anki (backend-backed → M2)

| Feature | Status | Notes |
|---|---|---|
| Collection open/close | ✅ | **Real Rust backend** (`AnkiCore.xcframework`, anki 25.09.2). `AnkiCollection` open/close; verified by integration tests + CI (run 28101322821) |
| Decks & subdecks | ✅ (read) | **Real** deck + subdeck names and live new/learn/review counts via `BackendCollectionGateway.deckTree()`; shown in deck list. Deck create/rename = later slice |
| Notes / cards / note types | ✅ | Real backend CRUD: read + addNote + updateNote + tags; manual creator (Basic/Cloze) + AI creator; integration-tested |
| Card templates & CSS | ✅ (read) | **Real backend `render_existing_card`** — question/answer HTML + note-type CSS; integration-tested (M2.2). Template editing not yet. |
| Front/back & HTML rendering | ✅ (read) | Reviewer renders backend-produced question/answer HTML + CSS in `CardWebView`; media `<img>` resolution still pending |
| MathJax rendering | ✅ | WKWebView + `\( \)`/`\[ \]`; bundle locally (M1 tail) |
| Hebrew / RTL | ✅ | `dir` preserved end-to-end; strip helpers tested |
| Mixed RTL/LTR | ✅ | per-span `dir` honored |
| Cloze cards | ✅ | Backend cloze rendering ([...]/answer) + manual & AI cloze creation; tested (BackendClozeTests) |
| Media (image/audio) | ✅ | Backend media folder set on open; appres:// rendering; media sync; device-verified (download/display) |
| Card browser | ✅ | Search + bulk suspend/unsuspend/move/flag/tag with per-item success/failure reporting |
| Note/card editing | ✅ | Real backend note editing (fields + tags + deck) + AI edit proposals; manual Add Card |
| Review screen | ✅ | Real queue + answer buttons + reviewer rendering + Ask Claude; device-verified scheduling delay |
| Answer buttons | ✅ | Real backend answerCard (Again/Hard/Good/Easy); tested |
| Undo / bury / suspend / flags / tags | ✅ | Real backend ops + tests (BackendBurySuspendUndoTests) |
| Filtered decks / custom study | ✅ | createFilteredDeck + custom study; tested |
| Statistics | ✅ | Backend graphs (reviews/future/added) + Insights; tested |
| Scheduling / learning-review-relearn steps | ✅ | Real scheduler queue; device-verified short learning delay |
| FSRS behavior & config | ✅ | Backend FSRS via deck config; tested |
| Timezone / day-rollover | ✅ | Backend day-boundary; tested (BackendDateBoundaryTests) |
| Collection DB compatibility | ✅ (verified) | reusing the canonical Rust backend; integration test proves a real `collection.anki2` opens and is **byte-identical** after read (no schema migration / destructive write) |
| Import/export (.apkg, colpkg) | ✅ | apkg/colpkg round trips pass on CI; malformed packages fail safe. Not device-verified |
| Backups & restoration | ✅ | Validated .colpkg backups to Documents/Backups (Files-visible) + restore; device-verified |
| Synchronization / AnkiWeb | ✅ | Download/two-way/media device-verified; full upload guarded + not device-verified |
| Settings/preferences | ◑ | AI settings ✅; collection prefs M2 |
| Notifications / reminders | ☐ | M3 |
| Background tasks | ☐ | M3 (iOS-constrained) |
| Sharing / file opening (.apkg) | ☐ | M2/M3 |
| Accessibility | ☐ | M3 |
| Dark mode | ◑ | SwiftUI + WebView dark CSS; audit M3 |
| Localization (incl. Hebrew) | ☐ | strings exist in fork; wire M1 tail/M3 |

## Custom AI features (this fork)

| Feature | Status | Notes |
|---|---|---|
| Claude API client (caching, images, usage) | ✅ | tested |
| Provider abstraction | ✅ | `AIChatAPIClient` |
| Prompt management (reviewer + creator, RTL/MathJax rules) | ✅ | verbatim port, tested |
| Ask-Claude reviewer chat | ✅ | VM tested; UI wired |
| Edit-card proposal + apply | ✅ | tested incl. note update |
| Add-card proposal (reviewer) | ✅ | tested |
| AI card creator (generate → review → add) | ✅ | VM tested; UI sheet |
| Creator image/PDF attachments | ✅ | PhotosPicker + PDF; file-backed scoped persistence (checksum/size/path-traversal guarded) |
| AI-generated HTML validation/insertion | ✅ | raw-HTML insertion path + parsing tested |
| MathJax produced by AI | ✅ | renderer honors enforced delimiters |
| AI insights / tip engine | ◑ | Engine + real revlog metrics (streak/retention/daily/time); avg-ease + per-deck retention not yet computed (PARTIAL) |
| Forced study mode | ◑ | Partial / platform-limited: notification + in-app session (no Android cross-app overlay) |
| Scheduler hint overlay | ☐ | M3 |
| Upstream update checker | ☐ | optional |
| API-key storage | ✅ | Keychain (upgrade) |
| Budget / spend tracking | ✅ | tested |
| Error handling (network/401/429/529) | ✅ | tested |
| Chat persistence (separate ai db) | ✅ | tested |
