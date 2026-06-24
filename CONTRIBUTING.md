# Contributing

## Ground rules
- The **Android source** (`C:\Users\Evyatar\AndroidStudioProjects\Anki-Android-AI`) is **read-only**.
  Never modify, create, format, build, or run git/destructive commands there. Verify
  `git -C <android> status` is unchanged after substantial work.
- All iOS code lives under this repository only.
- Native **Swift / SwiftUI** (UIKit/WKWebView where needed). No React Native / Flutter / KMP-UI /
  Compose / web wrappers. Port logic conceptually, not line-by-line.

## Workflow
1. Small, descriptive commits; never rewrite/squash history without being asked; no destructive git.
2. For each change: identify the Android behavior, write/adjust tests, implement, update
   `docs/feature-parity-checklist.md` + `docs/progress.md`, commit.
3. Don't mark a feature complete just because a similarly-named file exists — it must be implemented
   and tested/rendered end-to-end.
4. The authoritative build is macOS GitHub Actions; drive it green before claiming "compiles".

## Style
- Match surrounding code: focused views + `@MainActor` view models, `async/await`, dependency
  injection from `AppEnvironment`. No giant views, no global mutable state, no API calls from views.
- Keep the dependency surface minimal; justify any new package (license, maintenance, iOS support,
  native alternative) and record it in `docs/licensing-analysis.md` + `THIRD_PARTY_NOTICES.md`.

## Project regeneration
Edit `project.yml`, not the generated `.pbxproj`. Run `xcodegen generate` (Mac) to refresh.

## Secrets
Never commit keys/certs/profiles. Run `tools/secret-scan.sh` before pushing.
