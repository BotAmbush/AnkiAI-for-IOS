# Progress Ledger

Canonical status of the AnkiAI iOS migration. Updated after every milestone.

## Baseline (captured 2026-06-24)

- **Android source**: `C:\Users\Evyatar\AndroidStudioProjects\Anki-Android-AI` — **read-only**.
- **Android HEAD**: `9bad8304c8b7b013a6c977c20ebd9f726a436430` (branch `main`).
- **Android git status at start**: untracked screenshots / UI XML dumps / `.claude/settings.local.json` only — no tracked changes. These are pre-existing and **not** created by this migration.
- Fork base: upstream AnkiDroid `v2.25.0alpha1` (`711510ff`).
- Core engine: upstream **Rust `anki` backend** via `anki-android-backend` (rsdroid) `0.1.64-anki25.09.2`, wrapped by a thin Kotlin `libanki` (49 files). App layer: 681 Kotlin files.

> Verification protocol: after each milestone, confirm `git -C <android> status` is unchanged from the baseline above.

## Architecture decision (see decision-log.md DL-001)

Full data/scheduler/sync/FSRS/import-export parity requires **reusing the same upstream Rust `anki` backend compiled for iOS** (as official AnkiMobile does), wrapped by a Swift `libanki`-equivalent — *not* a Swift reimplementation of the scheduler. This is milestone 2.

The AI fork features are genuinely native Swift and are independent of the Rust backend except for collection reads/writes, which go through a `CollectionGateway` protocol.

## Milestones

### M1 — Native AI layer + app shell + CI (CI GREEN ✅)
Status: **macOS GitHub Actions build is green** — Xcode build SUCCEEDED, 38 unit tests passed
(0 failures) on the iOS Simulator, and `AnkiAI-unsigned.ipa` (Release `arm64` device build in
`Payload/`) was packaged and uploaded with diagnostics.

Verified run: `28097004935` (commit `a65dc65`). Build-repair loop took 3 runs:
- Run 1 — failed: runner Xcode 15.4 could not read XcodeGen's format-77 project → moved CI to
  macOS 15 + Xcode 16, added `mkdir build`, dynamic simulator selection.
- Run 2 — failed: one Swift error (`(try? await …) ?? (try await …)` illegal in a `??`
  autoclosure) → fixed; also abstracted `SecretStore` so the host-less test bundle doesn't need
  Keychain entitlements.
- Run 3 — **green**: build + 38 tests + unsigned IPA artifact.

Done:
- [x] Exhaustive read of the AI fork source (chat, creator, insights, forced-study, settings, API client, prompts, data layer).
- [x] XcodeGen project (`project.yml`), Info.plist, iOS 16 target, no-signing config.
- [x] GitHub Actions `workflow_dispatch` workflow: build (generic iOS device, unsigned) → unit tests (Simulator) → unsigned `AnkiAI-unsigned.ipa` in `Payload/` → upload IPA + logs + dSYMs.
- [x] **Native Claude API client** (`ClaudeAPIClient`) — full port incl. prompt caching, image messages, usage/cost callbacks, error mapping. Injectable transport for tests.
- [x] **Prompts** ported verbatim (RTL/Hebrew, MathJax delimiters, allowed-tag rules, JSON action protocol, creator static/dynamic prompts).
- [x] **Response parsing** (edit/add-card actions, creator JSON array, fenced-block extraction) — pure & tested.
- [x] **HTML/text helpers** (`stripHtml`, math-aware strip) — tested incl. Hebrew + MathJax markers.
- [x] **Pricing/budget** + user-facing error presenter.
- [x] **AI Insights tip engine** ported (priority sort, top-5).
- [x] **AI database** (`ai_insights.db`) over system libsqlite3 — chat messages DAO, separate from collection. Tested in-memory.
- [x] **Keychain** API-key storage (upgrade over Android SharedPreferences).
- [x] **Chat view model** (reviewer + creator) wired to gateway/db/client — tested with fakes.
- [x] **SwiftUI shell**: Decks / Insights / Settings tabs, reviewer with MathJax WebView, "Ask Claude" chat, AI creator sheet, settings with test-connection.
- [x] `CollectionGateway` abstraction + in-memory `StubCollectionGateway` so M1 runs end-to-end without the backend.
- [x] Test suite: parser, HTML, pricing, tips, database, client (fake transport), chat VM (fake client + stub gateway).

Next for M1:
- [ ] Trigger CI, read failure logs, drive build→green (see build-repair loop). **User must click Run workflow** (or authorize `gh`).
- [ ] Bundle MathJax locally instead of CDN (offline rendering parity).
- [ ] Localized strings (Hebrew/RTL) from `ai_strings.xml` / `values-iw`.

### M2.1 — Real Anki collection READ path (CI GREEN ✅, verified 2026-06-24)
Status: **complete and verified on macOS CI** — full pipeline green (run `28101322821`,
commit `d0656a1`): pinned Rust backend built for both iOS targets → `AnkiCore.xcframework`
assembled → app linked the real backend → **41 tests passed (0 failures)** incl. 3 backend
integration tests → unsigned IPA packaged and downloaded.

- [x] **Feasibility proven by CI** (GO): pinned `ankitects/anki` `25.09.2`
  (`3890e12c…`) + a narrow C-ABI bridge compile for `aarch64-apple-ios` and
  `-sim` (run `28099025800`). See `docs/anki-backend-ios-feasibility.md`, `docs/anki-backend-pin.md`.
- [x] Deterministic, **cache-free** backend build (`tools/build-anki-backend.sh`):
  submodule-aware clone; `anki_proto` built first (descriptor-race fix); bridge
  built per target; `xcframework` assembled.
- [x] **Swift bridge**: `AnkiCollection` (owns the C handle, open/deckTree/close),
  `BackendCollectionGateway` (actor) behind the existing `CollectionGateway` seam.
- [x] **Production no longer uses `StubCollectionGateway`** — deck list reads the
  real backend; stub is previews/tests only.
- [x] **Real deck tree**: real deck + subdeck names and live new/learn/review
  counts shown in the deck list (loading/error states; no fake data).
- [x] **Integration tests**: open a real fixture collection via the backend,
  assert real names + counts, and verify the canonical fixture is byte-identical
  (no destructive writes) + deterministic reopen.
- [x] Unsigned IPA now 4.5 MB / 13.9 MB arm64 executable (backend statically linked),
  verified Mach-O arm64, iOS 16.0.

Build-repair loop for M2.1 took 6 runs (submodule → tokio io-util → cache poisoning
→ build-script descriptor race → fixture/level assertions → green). Each fix documented.

Write/edit paths (note add/update, card context) intentionally throw
`GatewayError.notImplementedInM21` — they arrive with later M2 slices.

### M2.2 — Real card read + backend rendering (CI GREEN ✅, verified 2026-06-24)
Status: **green** (run `28114901645`, commit `9e6c2e2`): backend xcframework + app +
**45 tests (0 failures)** incl. 4 new render integration tests + 4.61 MB arm64 IPA.
- [x] Bridge: `anki_backend_deck_card_ids` (search cards by deck name),
  `anki_backend_render_card` (`render_existing_card` → question/answer HTML + CSS).
- [x] Swift: `AnkiCollection.cardIds(inDeckNamed:)` / `renderCard(cardId:)`,
  `RenderedCard`, gateway methods (Backend real; Stub preview-only).
- [x] `CardWebView` injects note-type CSS + wraps in `<div class="card">`.
- [x] `ReviewerView` loads real cards from a deck → renders question → reveal
  answer (backend HTML+CSS) → next-card paging; deck rows navigate into it.
- [x] Integration tests: real card ids; Hebrew render keeps `dir="rtl"` + `.card`
  CSS; Math keeps `\( \)`; answer ≠ question; canonical fixture byte-identical.
- One CI fix this slice: `search_cards` needs `&str` (TryIntoSearch), not `String`.
- Read-only: answer buttons, undo/bury/suspend, scheduler mutations, media `<img>`
  resolution remain for the next slice.

### M2.3 — Answer buttons + real scheduler write (CI GREEN ✅, verified 2026-06-24)
Run `28117704977`, commit `0e7ad03`: **48 tests (0 failures)**, 4.62 MB arm64 IPA.
- [x] Bridge `anki_backend_answer_card` → `col.grade_now`; ReviewerView shows
  Again/Hard/Good/Easy after reveal; grading drives the real scheduler + advances.
- [x] Integration test: grading every Math card "Easy" reduces the deck's new
  count (real write); canonical fixture byte-identical.
- CI fix: `grade_now` uses a 0-based rating scale (0=Again…3=Easy); bridge maps
  the external 1..=4 by subtracting 1.

### M2.4 — Undo / bury / suspend (CI GREEN ✅, verified 2026-06-24)
Run `28118887353`, commit `736d889`: **51 tests (0 failures)**, 4.65 MB arm64 IPA.
- [x] Bridge bury/suspend (`bury_or_suspend_cards`) + undo (`col.undo`); reviewer
  toolbar menu; integration tests (suspend/bury reduce new count; suspend→undo restores).

### M2.5 — Wire AI creator add-card to the backend (CI GREEN ✅, verified 2026-06-24)
Run `28120838056`, commit `ae8533d`: **53 tests (0 failures)**.
- [x] Backend gateway `addNote` + `basicNotetypeId` + `resolveOrCreateDeck` real;
  AI creator adds REAL cards. Integration test: add note → real deck shows 1 new
  card → searchable + renders the added front/back. CI fix: `return 1;` in the
  add_note JSON-parse error arm.

### M2.6 — Move card between decks (CI GREEN ✅, verified 2026-06-24)
Run `28121831458`, commit `34b9ef2`: **54 tests (0 failures)**.
- [x] Bridge `set_deck`; gateway `moveCard`; reviewer "Move to Default deck".
- [x] Integration test: moving all Math cards to Hebrew empties Math's due counts
  and grows Hebrew's; canonical fixture byte-identical.

### M2.7 — Card browser (CI GREEN ✅, verified 2026-06-24)
Run `28123587961`, commit `b84313b`: **58 tests (0 failures)**.
- [x] Bridge generic `search_cards`; Browse tab (deck:/tag:/free text); detail
  view; integration tests (empty=all 7, deck:Math=4, Hebrew=3, tag:vocab=2, free text).

### M2.8 — Live collection statistics (CI GREEN ✅, verified 2026-06-24)
Run `28124399945`, commit `cb0e7a4`: **59 tests (0 failures)**. Live counts in Insights.

### M2.9 — Flags + tags (CI GREEN ✅, verified 2026-06-24)
Run `28125950705`, commit `7f4b285`: **61 tests (0 failures)**.
- [x] Bridge `set_card_flag` + `add_tags_to_notes`; reviewer Flag submenu; tests
  via `flag:` / `tag:` search.

### M2.10+ — remaining core (NOT STARTED — larger slices)
- [ ] Note edit/cardContext (blocked: backend `get_note`/`get_card` not public —
  investigate a rendered-HTML workaround for AI card context).
- [ ] Media serving (`<img>`) to the WebView; import/export (.apkg/.colpkg);
  AnkiWeb sync; full statistics graphs; full note editor UI.

## Session summary (2026-06-24) — M2.1 → M2.9, all CI-verified green

Nine vertical slices landed green this session (latest run `28125950705`, **61
tests, 0 failures**). On top of the M2.1–M2.6 summary below, M2.7–M2.9 added:
card **browser** (arbitrary `deck:`/`tag:`/free-text search), live collection
**statistics** in Insights, and card **flags** + note **tags**. Feature map:
**18 completed**, 12 partial, 15 not_started, 1 blocked. Android unchanged
throughout (`9bad8304`, 0 tracked changes). Still Mode A;
`lastAndroidCommitFullyPortedToIOS` stays **null**.

---

### (earlier) M2.1 → M2.6 summary

The real Anki collection path now covers, end-to-end through the Rust backend
`AnkiCore.xcframework` (anki 25.09.2) with integration tests proving the canonical
fixture is never mutated:
- **Read**: open collection, deck tree (names + new/learn/review counts), list
  cards per deck, render question/answer + note-type CSS.
- **Write (scheduler/management)**: grade (Again/Hard/Good/Easy), bury, suspend,
  undo, move card between decks.
- **Notes**: add note (the AI card creator now adds REAL cards), resolve/create
  deck, Basic notetype id.
- **Reviewer UI**: deck → real cards rendered → Show Answer → grade buttons →
  next; toolbar Bury/Suspend/Move/Undo; Ask Claude.
- 54 unit + integration tests; unsigned arm64 IPA (~4.65 MB, backend linked).

Still Mode A (`initial-full-migration`); `lastAndroidCommitFullyPortedToIOS`
stays **null**. Notable gaps: note **editing** of existing cards + reviewer
card-context for AI (blocked on backend `get_note`/`get_card` not being public —
a workaround via rendered HTML is the next investigation), flags/tags, card
browser, full editor, media serving, statistics, import/export, sync,
notifications, localization, accessibility, forced-study.
- [ ] Scheduler/FSRS surfacing; statistics; filtered decks/custom study.
- [ ] Import/export (.apkg/.colpkg); backups; AnkiWeb sync.
- [ ] Wire AI write features (edit/add card) to the backend; live AI insights (revlog).

### M3 — Forced study, notifications, accessibility, polish (NOT STARTED)
- [ ] Forced-study enforcement (iOS analog of the Android overlay/foreground service — constrained by iOS background limits; see migration-risks.md).
- [ ] Notifications/reminders, dark mode polish, accessibility, full localization.

## Parity
See `feature-parity-checklist.md` for the per-feature completed/partial/unsupported breakdown.
