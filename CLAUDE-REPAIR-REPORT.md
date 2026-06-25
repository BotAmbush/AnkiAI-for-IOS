# Claude Repair Report — post-Codex-audit (2026-06-25)

An independent Codex audit concluded **NOT COMPLETE** and flagged a P0
remote-data-loss risk. This repository was **de-finalized** (Mode B → Mode A,
`lastAndroidCommitFullyPortedToIOS = null`) and entered a repair phase. This
report tracks the repairs. The migration will **not** be re-finalized until the
repairs land, CI is green, a new physical-device test passes, and a **second
independent audit** verifies completion.

## Status of audit findings

| # | Finding | Status |
|---|---------|--------|
| P0 | Seeded/unknown collection could replace remote AnkiWeb via full upload | **Fixed (R1)** — provenance gate + backup + double-confirm; seeded/unknown upload forbidden |
| — | Premature finalization | **Reverted (R1)** — baseline back to Mode A; statuses corrected |
| M1 | Sync hardening (BackgroundSync error persistence; full-download atomic/backup; device retest) | **Partial** — BackgroundSync now persists outcomes (full-sync-required / auth / media / network) and surfaces them on next launch; never auto-resolves full-sync. full_download already does temp+integrity+atomic; pre-upload backup added (R1). Device retest still required. |
| M2 | `.apkg` import/export real verification + rollback | **Hardened + honest (R5)** — import is transactional (backend rolls back on failure) + a pre-import .colpkg backup is written; malformed/missing-package failure + collection-preservation are tested. `.apkg` EXPORT verified. Happy-path `.apkg` IMPORT still hits an anki-internal deck-merge edge (decks.rs:141 'decks have different kinds') that needs LOCAL anki debugging; the WORKING package-import paths remain `.colpkg` restore (round-trip tested) + AnkiWeb sync. Kept **partial**. |
| M3 | Remove silent production failures; CardBrowser bulk per-item reporting | **Fixed (R2)** — runBulk reports total/succeeded/failed + first error; selection kept on partial/failure; no false success |
| M4 | AI Insights real revlog metrics (no placeholders) | **Partial (R3)** — real streak / avg reviews-per-day / avg seconds-per-card / today (from graphs) + retention/weak/mature; streak tip enabled. avg-ease + per-deck/worst-deck retention not yet computed (no placeholder shown). |
| M5 | forced-study classified partial/platform-limited + strongest iOS equivalent | **Done (R1)** — reclassified partial/platform-limited; the strongest valid iOS-native equivalent is implemented (repeating local notification + in-app non-dismissible required-N-review fullScreenCover session, with snooze) and unit-tested. Not described as equal to the Android cross-app overlay. |
| M6 | Broader integration fixtures + production-path tests | **Fixed (R4)** — anki_backend_create_large_fixture (~hundreds of cards, 7 decks/subdecks, Basic+Cloze, Hebrew/MathJax/Unicode, new/learning/review/future/suspended). Broad BackendCollectionGateway integration test: shape, states, cloze, Hebrew render, queue-excludes-suspended, real stats, colpkg round-trip at scale. (Full thousands-scale + corrupted/legacy-schema remains a device/manual concern.) |

## Overall repair status

- **Code-addressable findings: done.** P0 fixed; finalization reverted; bulk-op
  honesty (M3); BackgroundSync persistence (M1 partial); real Insights metrics (M4
  partial); forced-study reclassified + iOS equivalent (M5); broad fixtures (M6);
  `.apkg` import safety + tests (M2, kept partial).
- **State is honest:** `ANDROID-SOURCE-BASELINE.json` = Mode A
  (`initial-full-migration`, `lastAndroidCommitFullyPortedToIOS = null`,
  `initialMigrationCompleted = false`). Feature map: **41 completed, 5 partial, 0
  physical_device_verified**. CI `mode=full` green (run 28166484814, **136 tests**);
  new unsigned IPA produced.
- **NOT re-finalized.** Per the audit, this repair phase stops here and reports.

> A second device-repair phase followed (physical-device findings) — see
> "Device-repair phase 2" below. Current state: **42 completed / 4 partial / 9
> physical_device_verified**; CI green (run 28177577113, **149 tests**); still Mode A,
> NOT finalized.

## Device-repair phase 2 (physical-device findings) — 2026-06-25

The user retested on a real iPhone. Confirmed working (now recorded
`physical_device_verified: true`): full AnkiWeb **download**, **media** download,
**demo/seeded upload blocking**, normal **two-way sync**, **persistence** after
relaunch, **learning/relearning short delay**, **MathJax**. Full upload is NOT
device-verified (guarded). Three defects were found and fixed:

### Issue 1 — manual backup not accessible (FIXED, await device retest)
Root cause: backups were written to Documents but the app didn't expose Documents to
the Files app.
- **Files:** `project.yml` (`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`),
  `.github/workflows/ios.yml` (PlistBuddy verification of both keys in the COMPILED
  app), `AnkiAI/Platform/BackupService.swift` (new — validated atomic backups in
  `Documents/Backups`), `AnkiAI/Features/Settings/AISettingsView.swift` (validated
  flow + result presentation + Share/Save-to-Files), `BackupsListView.swift` (new),
  `ColpkgFile`.
- **Tests:** `BackupServiceTests` (destination, timestamped unique name, no illegal
  chars, failed-export→no-success+temp-cleanup, too-small/non-archive rejected, no
  overwrite, list+delete, real colpkg validates).
- **Verified:** the downloaded IPA's compiled `Info.plist` contains both keys.

### Issue 2 — no discoverable manual Add Card (FIXED, await device retest)
- **Files:** `AnkiAI/Features/Editor/ManualAddCardView.swift` (new — native
  Basic/Cloze: deck + fields + tags, required-field validation, REAL backend save,
  errors surfaced), `AnkiAI/Features/Decks/DeckListView.swift` (toolbar "+" + sheet).
- **Tests:** `BackendManualAddTests` (Basic note + tags in Browse; Cloze renders).

### Issue 3 — stale demo account / Logout did nothing (FIXED, await device retest)
Root cause: `ankiWebHKey` read directly (not observable) → Logout never re-rendered.
- **Files:** `AnkiAI/Security/KeychainStore.swift` (`isAnkiWebLoggedIn` +
  `logOutAnkiWeb()`), `AnkiAI/Features/Settings/AISettingsView.swift` (`@State
  loggedIn`, demo-not-authenticated note, immediate Logout that cancels sync + clears
  session, never touches the collection).
- **Tests:** `AnkiWebAuthStateTests` (demo not authenticated; login needs non-empty
  key; logout clears session/username/bg-state; logout preserves Claude key +
  collection).

### Delivery
- **CI:** run **28177577113** — green, **149 tests, 0 failures**
  (https://github.com/BotAmbush/AnkiAI-for-IOS/actions/runs/28177577113).
- **Commit:** `3f5f694` (main).
- **IPA:** `C:\AnkiAI-for-IOS\AnkiAI-unsigned.ipa`, **7,297,746 bytes**; compiled
  `Info.plist` verified: `UIFileSharingEnabled=true` +
  `LSSupportsOpeningDocumentsInPlace=true`.

### Exact physical-device retest steps (this delivery)
1. Files → Browse → On My iPhone → **AnkiAI → Backups** exists after "Back up
   collection"; the new `AnkiAI-Backup-<ts>.colpkg` is visible/non-empty/openable;
   Share + Save to Files work; Restore from it succeeds.
2. Decks → **"+" Add card** → create a Basic note and a Cloze note (deck + tags); both
   appear in Browse and survive a sync.
3. Fresh launch on the demo collection shows **"Not signed in / demo"**; after login,
   **Logout** immediately returns to the login form; the local cards remain.

## Remaining (NOT done by this repair phase)
1. **Physical-device retest** of backup / manual-add / auth-UI (steps above); plus
   continued device validation of sync/RTL/MathJax. Those three stay
   device-unverified until retested.
2. **Happy-path `.apkg` import** — needs LOCAL anki debugging of the deck-merge edge
   (`decks.rs:141`); `.colpkg`/sync are the working import paths meanwhile.
3. **AI Insights** — average ease + per-deck/worst-deck retention still uncomputed
   (no placeholder shown).
4. **A SECOND independent Codex audit** must verify completion before any
   re-finalization. Do not advance the baseline before that.

## R1 — P0 upload safety + de-finalization (this commit)

**Files changed:**
- `AnkiAI/Security/KeychainStore.swift` — `CollectionProvenance` enum +
  `AISettingsStore.collectionProvenance` / `isUploadForbidden`.
- `AnkiAI/App/AppEnvironment.swift` — seed → `.seededSample`; pre-existing
  untracked collection → `.unknown` (safe default).
- `AnkiAI/Features/Settings/AISettingsView.swift` — upload is BLOCKED for
  seeded/unknown collections; otherwise requires a local backup + an explicit
  destructive confirmation showing provenance + card/deck counts; never an
  automatic fallback. Provenance is set to `.downloadedFromAnkiWeb` on a
  successful download / normal sync and `.restoredFromBackup` on restore. Media
  sync errors are surfaced (no longer silently `try?`-dropped in these paths).
- `ANDROID-SOURCE-BASELINE.json` — reverted to Mode A (`under-repair`).
- `docs/android-update-history.md` — Entry 3 (de-finalization).
- `docs/android-ios-feature-map.yml` — sync/import/apkg/insights/forced-study →
  `partial`; all `physical_device_verified` reset to `false`.

**Tests added:** `AnkiAITests/CollectionProvenanceTests.swift` — default/unknown
and seeded provenance forbid upload; downloaded/restored/created allow it;
provenance persists.

## Physical-device tests still required
See `PHYSICAL-DEVICE-TEST-PLAN.md` (added after CI is green). Nothing in this
phase is "device-verified" until that plan is executed on a real iPhone.
