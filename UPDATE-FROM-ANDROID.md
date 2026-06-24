# Update the iOS App From Android

Entry point for any "update from Android" request (including Hebrew:
"עדכן את האפליקציה", "תעדכן לפי אנדרואיד"). **Always determine the mode first** —
do not assume a diff-only update.

A future Claude session must:

1. Read `CLAUDE.md` (the **Mandatory Android-to-iOS Lifecycle Protocol**).
2. Read `ANDROID-SOURCE-BASELINE.json`.
3. Determine the current migration mode from that file.
4. **If the initial migration is incomplete** (`initialMigrationCompleted: false`
   / `lastAndroidCommitFullyPortedToIOS: null` — the current state):
   - Do **NOT** perform a narrow incremental/diff update.
   - Continue the **initial full migration** instead — follow
     `CONTINUE-INITIAL-MIGRATION.md`.
   - Explain to the user that full baseline finalization has not happened yet, so
     commit-to-commit synchronization is not authoritative; the whole Android app
     remains the behavioral reference.
5. **If incremental update mode is enabled** (`incrementalUpdateModeEnabled: true`
   with a non-null fully-ported commit):
   - Run `tools/audit-android-update.ps1` (read-only) to produce a change report
     under `docs/updates/`.
   - Classify changes (behavioral-to-port vs Android-only vs backend/schema).
   - Map them through `docs/android-ios-feature-map.yml`.
   - Implement the relevant behavior in Swift/SwiftUI/backend code.
   - Update tests and docs; run the secret scanner.
   - Commit and push; run the full GitHub Actions build-repair loop until green.
   - Verify the unsigned IPA.
   - Update `ANDROID-SOURCE-BASELINE.json` and `docs/android-update-history.md`
     **atomically, only after full success**.

In all cases the Android repository
(`C:\Users\Evyatar\AndroidStudioProjects\Anki-Android-AI`) is **strictly
read-only**; never reset/clean/restore/stash/checkout/build it. If it has
uncommitted tracked changes, stop and report them.
