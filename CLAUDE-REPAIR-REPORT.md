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
| M2 | `.apkg` import/export real verification + rollback | Pending |
| M3 | Remove silent production failures; CardBrowser bulk per-item reporting | **Fixed (R2)** — runBulk reports total/succeeded/failed + first error; selection kept on partial/failure; no false success |
| M4 | AI Insights real revlog metrics (no placeholders) | **Partial (R3)** — real streak / avg reviews-per-day / avg seconds-per-card / today (from graphs) + retention/weak/mature; streak tip enabled. avg-ease + per-deck/worst-deck retention not yet computed (no placeholder shown). |
| M5 | forced-study classified partial/platform-limited + strongest iOS equivalent | Reclassified (R1); enforcement strengthening pending |
| M6 | Broader integration fixtures + production-path tests | Pending |

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
