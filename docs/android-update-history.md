# Android → iOS Update History

Append-only ledger of Android source snapshots and synchronization events.
**Never overwrite or delete entries.** New entries go at the bottom.

Each entry records the Android snapshot/commit, the iOS commit, the migration
mode, and parity status. An entry advancing `lastAndroidCommitFullyPortedToIOS`
may only be written during the explicit finalization (Mode A→B) or after a
successful incremental update (Mode B), atomically with
`ANDROID-SOURCE-BASELINE.json`.

---

## Entry 1 — Initial source snapshot (NOT a completed synchronization)

- **Date / UTC:** 2026-06-24T13:37:19Z
- **Event:** Establish permanent lifecycle infrastructure; record the Android
  source snapshot used for the ongoing initial full migration.
- **Android snapshot commit:** `9bad8304c8b7b013a6c977c20ebd9f726a436430` (branch `main`)
- **Android remote:** https://github.com/BotAmbush/Anki-Android-AI.git
- **iOS commit (at infra creation):** `1f0843c2265db4f7773acde25d7d48625580bf39`
- **Migration mode:** `initial-full-migration`
- **Parity status:** `partial`
- **initialMigrationCompleted:** `false`
- **incrementalUpdateModeEnabled:** `false`
- **lastAndroidCommitFullyPortedToIOS:** `null`

> ⚠️ **WARNING — this is a SOURCE SNAPSHOT, not a completed synchronization.**
> The iOS app is not yet a complete functional copy of the Android app. This
> commit is the *behavioral reference* for the initial full migration; it must
> NOT be interpreted as full parity, and future sessions must continue the
> initial full migration (Mode A) rather than diff-only synchronization.

### Major implemented areas (CI-verified at this snapshot)
- Native AI layer: Claude API client (prompt caching, image blocks, usage/cost,
  error mapping), prompt management, AI response parsing, reviewer/creator chat
  view models, AI insights tip engine, AI SQLite store, Keychain API-key storage.
- SwiftUI app shell (Decks / Insights / Settings), MathJax + Hebrew/RTL rendering.
- **Real Anki collection READ path (M2.1)**: open a real `collection.anki2` via
  the pinned Rust backend (`AnkiCore.xcframework`, anki 25.09.2) and list real
  decks/subdecks with live new/learn/review counts; integration-tested; CI green;
  unsigned arm64 IPA produced.

### Major missing / not-yet-ported areas
- Reviewer queue + answer buttons; undo/bury/suspend/flags/tags; scheduler/FSRS
  UI; learning/review/relearning step surfacing.
- Card browser; note/card editor; collection **write** paths (currently throw
  `notImplementedInM21`).
- Templates/CSS rendering pipeline; cloze; media; audio.
- Statistics; filtered decks; custom study.
- Import/export (.apkg/.colpkg); backups/restore; AnkiWeb sync.
- Notifications; background behavior; localization; accessibility.
- AI: wiring edit/add-card writes to the backend; live insights from revlog;
  image/PDF attachment capture UI; forced-study (iOS-constrained).
