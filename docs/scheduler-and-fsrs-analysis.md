# Scheduler & FSRS Analysis

## Key finding
AnkiDroid's scheduler and FSRS are **not implemented in Kotlin**. `libanki/.../sched/Scheduler.kt`
and `DeckNode.kt` are thin wrappers that delegate to the Rust `anki` backend
(`anki-android-backend`). Queue building, `answerCard`, learning/review/relearning steps,
interval/ease/FSRS-difficulty-stability math, day rollover, and v3 scheduler logic all live
in Rust `rslib`.

## Consequence for iOS
We reuse the **same Rust backend** (DL-001). Re-deriving FSRS or the scheduler in Swift would
risk divergence from the canonical algorithm and break cross-device review consistency, so we
do not. The Swift `Scheduler` wrapper (M2) will expose the same operations the Kotlin wrapper does:
- `getQueuedCards` / next card
- `answerCard(rating)` with the four buttons
- `bury` / `suspend` / `unbury`
- counts (new/learning/review) per deck
- FSRS parameters / optimize (delegated)
- custom study / filtered-deck rebuild

## Testing plan (M2)
Mirror the fork's instrumented expectations: scheduling transitions, timezone/day-boundary
behavior, FSRS outputs for fixture collections, and a sync-contract test asserting the Anki
schema is untouched (Android has `compat/AnkiSyncContractTest.kt`). Fixtures derived from legal
test data, never private collections.

## Until M2
The AI features that need scheduling data (`RevlogAnalyzer`, insights live stats, forced study)
run against the `CollectionGateway`. The stub provides representative data so the UI/engine are
exercised; real numbers arrive when the backend lands.
