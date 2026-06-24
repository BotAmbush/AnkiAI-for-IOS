# Android → iOS Lifecycle Workflow

Authoritative procedures for keeping the native iOS app aligned with the
customized Android fork. Read alongside the **Mandatory Android-to-iOS Lifecycle
Protocol** in `CLAUDE.md` and the mode flags in `ANDROID-SOURCE-BASELINE.json`.

Product chain (source of truth): **upstream AnkiDroid → customized Android fork →
native iOS**. The customized fork is the behavioral source of truth; iOS never
ports directly from upstream while ignoring fork customizations.

Android source (`C:\Users\Evyatar\AndroidStudioProjects\Anki-Android-AI`) is
**strictly read-only** in every workflow below.

---

## Determining the mode (always do this first)

Read `ANDROID-SOURCE-BASELINE.json`:
- `migrationMode: "initial-full-migration"` and `lastAndroidCommitFullyPortedToIOS: null`
  → **Initial full migration** (Mode A). This is the current state.
- `incrementalUpdateModeEnabled: true` (and a non-null fully-ported commit)
  → **Incremental synchronization** (Mode B).

A generic "update" request is interpreted according to the mode (see CLAUDE.md
trigger phrases).

---

## A. Initial full migration workflow (Mode A — current)

While the full-port baseline is `null`:

1. Read the full feature map (`docs/android-ios-feature-map.yml`) and parity
   checklist (`docs/feature-parity-checklist.md`).
2. Select the next highest-priority missing vertical slice from
   `docs/implementation-roadmap.md` (continue existing milestones; do not restart).
3. Inspect **all relevant Android behavior** for that slice — the whole
   implementation at `androidSourceSnapshotCommit`, **not** only recent Git changes.
   Unchanged Android files are NOT assumed ported.
4. Implement native iOS parity (Swift / SwiftUI / Rust backend bridge) behind the
   existing `CollectionGateway`/backend seam.
5. Add or update tests (unit + integration as appropriate).
6. Update `docs/progress.md`, `docs/feature-parity-checklist.md`, and the
   `status`/`verification` fields in `docs/android-ios-feature-map.yml`.
7. Run the secret scanner; commit and push coherent changes.
8. Run the GitHub Actions Xcode build-repair loop (`mode=full`): build → fix the
   first real root cause → re-run until green.
9. Verify the unsigned IPA where appropriate (download, confirm arm64 Mach-O).
10. Continue until all required features are complete.
11. **Do NOT finalize the baseline automatically** — finalization is a separate,
    explicit, user-confirmed step.

In Mode A, "update the iOS app" / "update from Android" / "עדכן את האפליקציה" means
**continue this workflow**, not a diff-only update. See
`CONTINUE-INITIAL-MIGRATION.md`.

---

## B. Initial migration finalization workflow (explicit, gated)

Runs ONLY from an explicit finalization request (`FINALIZE-INITIAL-MIGRATION.md`),
never implicitly from a generic "update". All steps must pass:

1. Fresh, exhaustive parity audit against the Android snapshot.
2. Verify every discovered feature (not by filename — by behavior + tests).
3. Verify persistence / data compatibility (round-trip, no destructive writes).
4. Verify scheduler and FSRS behavior.
5. Verify import/export and synchronization.
6. Verify real collection behavior (open/edit/review/sync on real data).
7. Run the complete automated test suite (green).
8. Run GitHub Actions (green).
9. Verify the physical-device IPA (and, ideally, an actual device install).
10. Record unsupported iOS platform differences honestly.
11. Require **explicit user confirmation** before changing, atomically:
    - `initialMigrationCompleted` → `true`
    - `incrementalUpdateModeEnabled` → `true`
    - `lastAndroidCommitFullyPortedToIOS` → the verified Android commit
    and appending a finalization entry to `docs/android-update-history.md`.

A green compile, an IPA, or a filename-complete feature map are individually
**insufficient** to finalize.

---

## C. Future incremental synchronization workflow (Mode B — after finalization)

1. The user updates and tests the customized Android fork, and **commits** the
   Android changes.
2. Claude reads `ANDROID-SOURCE-BASELINE.json`.
3. Claude verifies Android HEAD and working-tree status (read-only).
4. Claude compares `lastAndroidCommitFullyPortedToIOS` with current Android HEAD.
5. Claude produces a classified change report (`tools/audit-android-update.ps1`
   writes raw Git evidence to `docs/updates/`).
6. Claude maps changes through `docs/android-ios-feature-map.yml`.
7. Claude implements all relevant behavior in Swift/SwiftUI/backend code.
8. Claude updates tests.
9. Claude runs the secret scanner.
10. Claude commits and pushes.
11. Claude runs and repairs the GitHub Actions build-repair loop.
12. Claude verifies the unsigned IPA.
13. Claude updates the baseline and history **atomically, only after full success**.

---

## Edge-case handling (all modes)

- **Uncommitted Android tracked changes**: STOP. Report the exact files. Do not
  reset/clean/restore/stash/checkout. The audit script exits non-zero.
- **Rewritten Android history** (recorded baseline commit missing from Android):
  do not guess. Report the missing commit; ask the user to confirm the new
  history / re-establish a baseline before any diff is trusted.
- **Missing baseline commit**: treat as "cannot diff"; in Mode A this is fine
  (use the snapshot as full reference); in Mode B, halt diff and report.
- **Schema changes** (collection DB): re-verify the pinned `anki` backend
  (`docs/anki-backend-pin.md`) covers the new schema; bump the pin only with a
  fresh feasibility + integration test; never silently migrate user data.
- **Rust backend changes**: if the Android fork bumps `anki-android-backend`,
  re-pin upstream anki, rebuild `AnkiCore.xcframework`, re-run integration tests,
  and update `docs/anki-backend-pin.md` before advancing.
- **Partial update completion**: never advance `lastAndroidCommitFullyPortedToIOS`;
  record progress in history as "partial" and continue.
- **Features without a valid iOS equivalent** (platform-only): mark `unsupported`
  in the feature map with a clear rationale; do not fake an implementation.
- **CI failures**: stay in the build-repair loop; do not declare success or
  advance the baseline on red.
- **Licensing blockers** (AGPL of the linked anki backend): treat as a release
  blocker (`docs/licensing-analysis.md`); does not block development but must be
  resolved before distribution.
