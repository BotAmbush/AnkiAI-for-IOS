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

## Remaining (NOT done by this repair phase)
1. **Physical-device validation** — execute `PHYSICAL-DEVICE-TEST-PLAN.md` on a real
   iPhone (real AnkiWeb full download + two-way + media sync + safe push-back, RTL/
   MathJax). Nothing is device-verified until then.
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
