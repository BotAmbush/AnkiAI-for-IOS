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

### M2 — Rust anki backend integration (NOT STARTED)
- [ ] Build `anki` rslib as an `xcframework` (uniffi/protobuf bridge) in CI on macOS.
- [ ] Swift `libanki`-equivalent: Collection open/close, Decks, Notes, Cards, Notetypes, Scheduler, FSRS, Media, import/export, sync.
- [ ] Replace `StubCollectionGateway` with `BackendCollectionGateway`.
- [ ] Then: real deck list/counts, real reviewer queue + answer buttons + undo/bury/suspend, card browser, editor, stats, filtered decks, backups, AnkiWeb sync.

### M3 — Forced study, notifications, accessibility, polish (NOT STARTED)
- [ ] Forced-study enforcement (iOS analog of the Android overlay/foreground service — constrained by iOS background limits; see migration-risks.md).
- [ ] Notifications/reminders, dark mode polish, accessibility, full localization.

## Parity
See `feature-parity-checklist.md` for the per-feature completed/partial/unsupported breakdown.
