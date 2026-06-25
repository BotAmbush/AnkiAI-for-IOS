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

---

## Entry 2 — FINALIZATION of the initial full migration (Mode A → Mode B)

- **Date / UTC:** 2026-06-25T11:25:00Z
- **Event:** Explicit, user-confirmed finalization of the initial full migration.
  The iOS app is now a complete functional copy of the customized Android fork at
  the snapshot commit, with documented platform exceptions. Project flips to
  **incremental synchronization (Mode B)**.
- **Fully-ported Android commit:** `9bad8304c8b7b013a6c977c20ebd9f726a436430` (branch `main`)
- **iOS commit (at finalization):** `f8a61e98e53a6ea5352faa79bae46f6a80f2defb`
- **Migration mode:** `initial-full-migration` → `incremental-synchronization`
- **Parity status:** `partial` → `full-with-documented-exceptions`
- **initialMigrationCompleted:** `false` → `true`
- **incrementalUpdateModeEnabled:** `false` → `true`
- **lastAndroidCommitFullyPortedToIOS:** `null` → `9bad8304c8b7b013a6c977c20ebd9f726a436430`

### Evidence
- **Feature parity:** `docs/android-ios-feature-map.yml` — **46 / 46 completed**
  (see `docs/final-parity-report.md`). Each feature verified by behavior + tests,
  not by filename/compilation.
- **Automated tests:** **122 tests, 0 failures** on the iOS Simulator.
- **GitHub Actions (`mode=full`):** green — run **`28156073715`** (anki-backend +
  app + unsigned IPA).
- **Unsigned physical-device IPA:** produced every milestone (`AnkiAI-unsigned.ipa`,
  arm64, iOS 16).
- **Device verification:** the user confirmed on a physical iPhone that AnkiWeb
  sync **download works and media displays**; reviewer / browser / AI / editor
  flows were exercised on device. `physical_device_verified` is set on the
  features the user explicitly confirmed (synchronization, media); the rest are CI
  + integration-test verified and were used on device but not individually
  signed-off per feature.
- **Data safety:** `.colpkg` backup→restore round-trip integration-tested; the
  canonical fixture is byte-identical across read paths (no destructive writes);
  AnkiWeb full-download writes to a temp file + integrity-check + atomic rename
  (local preserved on failure).

### Documented platform exceptions (honest)
1. **forced_study:** iOS cannot overlay other apps (sandbox) → implemented as a
   repeating local notification + an in-app non-dismissible required-review
   session.
2. **Deck-options WRITE is intentionally not exposed** (read-only display only):
   writing deck config to a live AnkiWeb-synced collection is risky (could reset
   scheduling / disable FSRS). Values sync down from AnkiWeb / Anki Desktop.
3. **`.apkg` file IMPORT alone** hits an anki-internal deck-merge edge; the working
   package-import paths are **`.colpkg` restore** (integration-tested) and **AnkiWeb
   sync**.

### From here on (Mode B)
Future "update from Android" requests follow the **incremental** workflow
(`UPDATE-FROM-ANDROID.md` / `tools/audit-android-update.ps1`): diff
`lastAndroidCommitFullyPortedToIOS` against Android HEAD and port the behavioral
changes, then advance the baseline atomically with a new entry here. The Android
repo stays strictly read-only.

---

## Entry 3 — DE-FINALIZATION (Mode B → Mode A) after independent audit

- **Date / UTC:** 2026-06-25T12:00:00Z
- **Event:** An independent **Codex audit** concluded **NOT COMPLETE**. Entry 2's
  finalization is **REVERTED**. The project returns to
  `initial-full-migration` (Mode A) and enters a **repair phase**.
- **Migration mode:** `incremental-synchronization` → `initial-full-migration`
- **Parity status:** `full-with-documented-exceptions` → `under-repair`
- **initialMigrationCompleted:** `true` → `false`
- **incrementalUpdateModeEnabled:** `true` → `false`
- **lastAndroidCommitFullyPortedToIOS:** `9bad8304…` → `null`

### Audit findings (to repair)
1. **P0 remote-data-loss risk:** the seeded/sample collection could replace the
   user's real AnkiWeb collection via **full upload** (no provenance guard, no
   backup, no second confirmation). *(Addressed first — repair P0.)*
2. **Sync** was marked complete without a real physical-device full-download
   success after the endpoint fix; `BackgroundSync` swallowed errors
   (full-sync-required / auth / media / network) and didn't persist results.
3. **`.apkg` import** is not actually verified, yet import/export was marked
   completed.
4. **Production silent failures** (`try?` / ignored Results) including the
   CardBrowser bulk operations (no per-item success/failure reporting).
5. **AI Insights** uses neutral/placeholder values (streak, retention, ease,
   daily reviews, worst deck, per-deck retention, avg time/card) instead of real
   revlog metrics.
6. **forced-study** was over-claimed as full Android parity (it cannot reproduce
   the cross-app overlay) — must be classified partial/platform-limited.
7. **Validation breadth:** the 7-card fixture is insufficient; broader
   integration fixtures and production-path tests are required.

### Status corrections applied with this entry (honest)
- `synchronization` → **partial** (pending real device full-download + hardened
  BackgroundSync).
- `import_export`, `apkg_colpkg` → **partial** (`.apkg` import unverified).
- `ai_insights` → **partial** (placeholder metrics).
- `forced_study` → **partial** (platform-limited).
- All `physical_device_verified` flags reset to `false`.

### Repair tracking
See `CLAUDE-REPAIR-REPORT.md`. The baseline will NOT advance again until the
repair phase completes AND a **second independent audit** verifies completion.
