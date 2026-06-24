# Finalize the Initial Migration (Mode A → Mode B)

**This is an explicit, gated, one-time transition. It must NEVER run implicitly
from a generic "update" request.** Run it only when the user explicitly asks to
finalize the migration AND the full port genuinely appears complete.

Finalization flips the project from the initial full migration to incremental
synchronization. Until it succeeds with explicit user confirmation, every
"update" continues the initial full migration.

## Hard preconditions (all must hold — verify, do not assume)

1. A **fresh, exhaustive parity audit** against the Android snapshot has been done.
2. **Every** discovered Android feature has a documented parity status in
   `docs/android-ios-feature-map.yml` and `docs/feature-parity-checklist.md`,
   verified by **behavior + tests**, not by filename or compilation.
3. Persistence / data compatibility verified (round-trip; no destructive writes).
4. Scheduler and FSRS behavior verified.
5. Import/export and synchronization verified.
6. Real collection behavior verified (open / edit / review / sync on real data).
7. The complete automated test suite passes.
8. GitHub Actions is green (`mode=full`).
9. The physical-device unsigned IPA is verified (ideally installed on a device).
10. Unsupported iOS platform differences are recorded honestly (`unsupported` in
    the feature map with rationale).

## Explicit confirmation gate

Do not proceed past this point without the user explicitly confirming
finalization for a specific Android commit.

## Atomic finalization (only after the gate)

Perform together, in one commit, atomically:

1. In `ANDROID-SOURCE-BASELINE.json`:
   - `lastAndroidCommitFullyPortedToIOS` ← the verified Android commit (was `null`)
   - `initialMigrationCompleted` ← `true`
   - `incrementalUpdateModeEnabled` ← `true`
   - `migrationMode` ← `"incremental-synchronization"`
   - `parityStatus` ← an honest value (e.g. `"full-with-documented-exceptions"`)
   - `lastAndroidCommitReviewedForIOS` ← the same commit
   - update `capturedAtUtc`
2. Append a finalization entry to `docs/android-update-history.md` recording the
   evidence (test run, CI run id, IPA verification, device check, exceptions).
3. Update `docs/progress.md` and `docs/feature-parity-checklist.md` accordingly.

## Invariants (never violate)

- A green compile alone cannot finalize. An IPA alone cannot finalize. A
  filename-only "completed" feature map cannot finalize.
- Baseline advancement is atomic with history recording.
- Never discard the last known successful full-synchronization baseline.
- A failed or partial state must NOT advance `lastAndroidCommitFullyPortedToIOS`.

After finalization, future "update from Android" requests follow the incremental
workflow in `UPDATE-FROM-ANDROID.md` / `docs/android-ios-lifecycle-workflow.md`.
