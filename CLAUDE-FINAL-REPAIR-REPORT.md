# Claude Final Repair Report — third independent Codex audit

The third independent audit (`CODEX-THIRD-INDEPENDENT-AUDIT.md`) returned **REPAIR
REQUIRED** (one residual P1 + three P2 + one P3). This pass fixes all five, strictly
in scope. The migration is **NOT finalized**: `migrationMode = initial-full-migration`,
`initialMigrationCompleted = false`, `incrementalUpdateModeEnabled = false`,
`lastAndroidCommitFullyPortedToIOS = null`. Android source untouched (0 changes).

## Findings → fix

| # | Finding (severity) | Fix |
|---|---|---|
| 1 | **P1** — AI creator can still fall back to the first deck when none is selected | `generateCards` now REQUIRES a valid `selectedDeckId`/path and aborts with "Select a destination deck" otherwise; removed `allDecks.first ?? "Default"`. `addCardFromProposal` uses the selected deck (or, only on explicit `useModelDeck`, the model's) — removed the `selectedDeckId ?? proposal.deckId` fallback. The deck is revalidated on relaunch (`load`) and before add; a deleted deck is cleared and the user must reselect. UI disables Generate/Add and shows a "Select a deck" affordance. |
| 2 | **P2** — Reviewer add-card can default to deck id 1 after resolution failure / creates the deck before approval | `AddCardProposal` no longer carries a pre-resolved `deckId`; `handleAssistantReply` no longer resolves/creates a deck. `approveAddCardProposal` resolves an EXISTING deck by name only at approval; a missing deck sets `pendingAddCardMissingDeck` (explicit "Create & add" or pick another existing deck via `addProposalToExistingDeck`). Never mutates before approval, never defaults to deck id 1, surfaces backend errors. |
| 3 | **P2** — Oversized/failed creator attachment persistence silently ignored while still sent | `setAttachments` now THROWS; `attachFiles` surfaces an actionable message with the exact per-file (20 MB) / per-session (80 MB) limit; only successfully-stored attachments are kept and sent. Restore keeps refs/payloads/`attachmentCount` in sync (drops missing/corrupt files). |
| 4 | **P2** — APKG pre-import backup failure ignored (`try?`) | `importApkg` now makes the pre-import `.colpkg` backup MANDATORY and verified (exists + > 256 bytes); on failure it throws `GatewayError.backupRequired` and ABORTS the import (no silent bypass). Backend transaction/rollback safety preserved. |
| 5 | **P3** — Stale docs/comments | Fixed the `CreatorSessionStore` base64 comment (now metadata-only refs); added an ARCHIVE banner over the superseded M1/M2 "blocked/stubbed/APKG-blocked" sections in `known-issues.md`; updated `progress.md`. |

## Files changed
- `AnkiAI/AI/AIModels.swift` — `AddCardProposal` drops the pre-resolved `deckId`.
- `AnkiAI/AI/Chat/AIChatViewModel.swift` — creator deck requirement + revalidation;
  throwing attachments + `attachFiles` + `attachmentErrorMessage`; reviewer
  approval-time deck resolution + missing-deck flow; restore ref/payload sync.
- `AnkiAI/Features/Chat/ChatView.swift` — Generate/Add gated on a selected deck +
  "Select a deck" prompt; attachment picking routed through `attachFiles` (surfaces
  failures); reviewer "Create deck?" confirmation alert.
- `AnkiAI/Backend/BackendCollectionGateway.swift` — mandatory verified pre-import backup.
- `AnkiAI/Domain/DomainModels.swift` — `GatewayError.backupRequired`.
- `AnkiAI/Domain/StubCollectionGateway.swift` — `lastAddedDeckId` (test support).
- `AnkiAI/AI/CreatorSessionStore.swift` — corrected comment.
- Docs: `docs/known-issues.md`, `docs/progress.md`, this report.

## Tests added
- `AIReviewerAddCardTests` — approval adds to existing deck; missing deck requires
  confirmation with NO mutation; never deck id 1; alternative existing-deck selection;
  cancel leaves the collection unmutated.
- `AICreatorAttachmentTests` — oversized surfaced + not kept/sent; valid kept; retry
  after failure; attachment count matches persisted after relaunch.
- `AICreatorDeckDuplicateTests` — no-selected-deck blocks generation and insertion;
  deleted selected deck blocks generation (and clears selection) and blocks add.
- `BackendApkgRoundTripTests` — import blocked when the mandatory pre-import backup fails.
- Updated creator tests to select a deck (the new requirement).

## Validation
Searched production code: no reachable `allDecks.first` deck-selection fallback, no
deck-id-1 default in add paths, no `try?`/ignored errors in attachment persistence or
the pre-import backup. Remaining `allDecks.first { $0.id == … }` uses are find-by-id
name lookups for display, not deck selection.

## Delivery
- **CI run:** 28299778258 — green, **230 tests, 0 failures**
  (https://github.com/BotAmbush/AnkiAI-for-IOS/actions/runs/28299778258).
- **Final commit (verified IPA):** `d8de59c`.
- **IPA:** `C:\AnkiAI-for-IOS\AnkiAI-unsigned.ipa`, **7,489,914 bytes**. Verified: arm64
  Mach-O device executable (`cffa edfe 0c00 0001`), ~22 MB executable with the real anki
  Rust backend statically linked, no XCTest/test payload, no `_CodeSignature`/
  `.mobileprovision`, no embedded `sk-ant-` secret, MathJax bundled, `Info.plist` has
  `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`, min iOS 16.
  (A docs-only commit follows; it does not change the binary.)

## Remaining physical-device validation gaps (NOT device-verified)
- AI creator on device: deck selection enforced; attachment size-limit messaging;
  duplicate prevention on accept→regenerate.
- Reviewer add-card with a missing/typo'd deck (Create-vs-pick-another flow).
- APKG import on a physical device (round trip + backup-abort are CI-verified only).
- Full AnkiWeb upload remains guarded and not device-verified.
- AI Insights average-ease + per-deck/worst-deck retention remain uncomputed (partial).

Per instructions, this pass STOPS after the green CI run and report. The migration is
not finalized.
