# Claude Third Repair Report — second independent Codex audit

The second independent Codex audit returned **REPAIR REQUIRED** (no P0 remaining; P1s
outstanding). This pass addresses all six requested repairs. The migration is **NOT
finalized**: `initialMigrationCompleted = false`, `incrementalUpdateModeEnabled = false`,
`lastAndroidCommitFullyPortedToIOS = null`, `migrationMode = initial-full-migration`.
The Android source was treated as strictly read-only (0 changes).

## Findings → fix status

| # | Audit finding | Status | Evidence |
|---|---|---|---|
| Repair 1 | AI creator not wired to the deck picker | **FIXED** | `CreatorDeckBar` + `DeckPickerSheet` in `ChatView`; `selectedDeckId/path` persisted in `CreatorSessionStore` and restored; passed as explicit DEFAULT DECK; insert uses the SELECTED deck (never `allDecks.first`), re-resolves + stops if the deck is gone; model-proposed different deck requires explicit "use suggested deck". |
| Repair 2 | Attachments stored inline as base64; retry state not persisted | **FIXED** | `CreatorAttachmentStore` writes scoped files (`Application Support/CreatorSessions/<id>/Attachments/`), metadata-only in JSON, per-file 20MB / per-session 80MB limits, checksum + size + path-traversal validation, cleanup on clear; `repairAttempted` + selected deck persisted; deck list re-resolved live (not persisted). |
| Repair 3 | Regenerate/repair can duplicate accepted cards | **FIXED** | `CardFingerprint` (HTML/whitespace-normalized) + per-session accepted ledger (persisted, survives regenerate/repair/relaunch); recorded only after a successful insert; duplicate requires explicit "Add anyway". |
| Repair 4 | APKG happy-path import not asserted | **FIXED (CI round-trip passes)** | Real blocker was `import_apkg` failing with "attempted media operation without media folder set" — the main handle opened with no media folder. `anki_backend_open` now sets `with_desktop_media_paths()`. `BackendApkgRoundTripTests` (export→fresh-import + double round trip; notes/cards/decks/subdecks/suspended/Hebrew preserved) pass on CI. |
| Repair 5 | AI Insights fabricated retention = 0.85 | **FIXED** | `InsightStats.retention30d` is `Float?` (nil = not enough data); `AITipEngine` emits a retention tip only when non-nil; `InsightsView` passes nil when no 30-day reviews. Average ease + per-deck retention remain **partial**. |
| Repair 6 | Stale/contradictory status docs | **FIXED** | Feature map: synchronization is one authoritative status (no "completed + reverted to partial"); import_export/apkg_colpkg → completed (round-trip CI-tested); ai_insights + forced_study stay partial. `feature-parity-checklist.md` banner points to the feature map as authoritative + stale M2 ☐/🔬 rows corrected. |

## Files changed
- Backend: `rust/anki-backend-ios/src/lib.rs` (`anki_backend_open` sets the media folder).
- AI: `AnkiAI/AI/AILanguage.swift` (existing), `AIModels.swift` (parse outcome — prior),
  `AI/Chat/AIChatViewModel.swift` (deck selection, file attachments, dup ledger, retry
  state, re-resolve decks, clear), `AI/CreatorSessionStore.swift` (metadata attachments
  + new fields), `AI/CreatorAttachmentStore.swift` (new), `AI/CardFingerprint.swift` (new),
  `AI/Insights/AITipEngine.swift` (optional retention).
- UI: `Features/Chat/ChatView.swift` (CreatorDeckBar, deck picker, duplicate alert,
  attachment routing), `Features/Editor/DeckPickerSheet.swift` (existing),
  `Features/Insights/InsightsView.swift`.
- Test support: `Domain/StubCollectionGateway.swift` (`lastAddedDeckId`).
- Docs: feature map, feature-parity-checklist, progress, known-issues, this report.

## Tests added
`AICreatorDeckDuplicateTests` (deck persistence, add-to-selected-deck, missing-deck
stop, accept→regenerate/repair/relaunch dedup, whitespace/HTML dup, different card,
override, failed-insert-no-fingerprint), `CreatorAttachmentStoreTests` (scoped file
save/restore, checksum/size/missing/path-traversal/oversize rejection, clear cleanup),
`CardFingerprintTests`, `AILanguageTests`, `AIResponseParserRecoveryTests` (prior),
`BackendApkgRoundTripTests` (export→fresh-import + double round trip), updated
`AICreatorSessionTests` (metadata attachments, no base64 in JSON), `PricingAndTipsTests`
(nil retention → no tip).

## Delivery
- **APKG happy-path round trip: PASS on GitHub Actions.**
- **CI run:** 28247367888 — green, **217 tests, 0 failures**
  (https://github.com/BotAmbush/AnkiAI-for-IOS/actions/runs/28247367888).
- **Commit (verified IPA):** `a4e13f0`.
- **IPA:** `C:\AnkiAI-for-IOS\AnkiAI-unsigned.ipa`, **7,477,195 bytes**. Verified: arm64
  Mach-O device executable (`cffa edfe 0c00 0001`), real anki Rust backend statically
  linked (~22MB executable), no XCTest/test payload, MathJax `tex-mml-svg.js` bundled,
  compiled `Info.plist` has `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`,
  no `.mobileprovision`/certs/secrets embedded.
  (A docs-only commit follows this report; it does not change the binary.)

## Remaining device-validation gaps (NOT device-verified)
- AI creator on device: deck selection lands in the chosen deck; attachments persist
  across relaunch; duplicate prevention on accept→regenerate.
- APKG import on a physical device (round trip is CI-verified, not device-verified).
- Full AnkiWeb **upload** remains guarded and not device-verified.
- AI Insights average-ease + per-deck/worst-deck retention remain uncomputed (partial).

## Unresolved issues
None blocking from this audit. Per instructions, this pass STOPS after the green CI run,
verified IPA and report. The migration is not finalized; awaiting a third independent
Codex audit.
