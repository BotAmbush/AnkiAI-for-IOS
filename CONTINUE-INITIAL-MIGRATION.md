# Continue the Initial Full Migration

**Use this when the initial Android→iOS migration is still in progress**
(`ANDROID-SOURCE-BASELINE.json` → `initialMigrationCompleted: false`,
`lastAndroidCommitFullyPortedToIOS: null`). This is the current state.

A future Claude session must:

1. Read `CLAUDE.md` — especially the **Mandatory Android-to-iOS Lifecycle Protocol**.
2. Read `ANDROID-SOURCE-BASELINE.json` and **confirm `initialMigrationCompleted` is `false`**.
   If it is `true`, do NOT use this file — use `UPDATE-FROM-ANDROID.md` instead.
3. Read `docs/android-ios-feature-map.yml`, `docs/feature-parity-checklist.md`,
   `docs/implementation-roadmap.md`, and `docs/progress.md`.
4. Pick the **next incomplete feature** (status `not_started` / `partial` / `blocked`)
   by roadmap priority — continue existing milestones; do not restart the architecture.
5. **Inspect the full relevant Android implementation** at
   `androidSourceSnapshotCommit` (the whole behavior, READ-ONLY) — not just Git
   changes, and never assume an unchanged Android file is already ported.
6. Implement the native iOS functionality (Swift / SwiftUI / Rust backend bridge)
   behind the existing `CollectionGateway` / `AnkiCore.xcframework` seam.
7. Add or update tests (unit + integration).
8. Run the secret scanner (`tools/secret-scan.sh`); commit and push coherent changes.
9. Run the GitHub Actions Xcode build-repair loop (`mode=full`) until green; verify
   the unsigned IPA where appropriate.
10. Update `docs/progress.md`, the parity checklist, and the `status`/`verification`
    fields in `docs/android-ios-feature-map.yml`.
11. **Preserve the Android source** (strictly read-only) and all existing work,
    tests, CI, docs, history, and backend.
12. **Never** use diff-only / incremental synchronization while in this mode, and
    **never** finalize the baseline automatically. Finalization is a separate,
    explicit, user-confirmed step (`FINALIZE-INITIAL-MIGRATION.md`).
