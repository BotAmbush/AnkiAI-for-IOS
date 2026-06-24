# Building

The project is defined declaratively in `project.yml` and the Xcode project is **generated** with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The committed source of truth is `project.yml`;
`AnkiAI.xcodeproj` is git-ignored and regenerated on demand.

## On a Mac (local)
```bash
brew install xcodegen
xcodegen generate
open AnkiAI.xcodeproj          # or build from CLI below
```

Build for a generic iOS device, unsigned:
```bash
xcodebuild -project AnkiAI.xcodeproj -scheme AnkiAI -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO clean build
```

Run unit tests on a Simulator:
```bash
xcodebuild -project AnkiAI.xcodeproj -scheme AnkiAI \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' test
```

## On Windows (this dev machine)
Xcode cannot run here. Use the GitHub Actions workflow as the authoritative build:

1. Push your branch.
2. GitHub → **Actions** → **iOS Build & Test** → **Run workflow** (`workflow_dispatch`).
3. When it finishes, download artifacts: `AnkiAI-unsigned-ipa` and `diagnostics` (logs, test
   results, dSYMs).

The workflow regenerates the project (XcodeGen), builds unsigned for a generic device, runs unit
tests on Simulator, and packages `Payload/AnkiAI.app` → `AnkiAI-unsigned.ipa`.

## Requirements
- iOS deployment target **16.0** (see `docs/decision-log.md` DL-004).
- No third-party Swift packages are bundled today (system SQLite + URLSession), so package
  resolution cannot break CI.

## Milestone 2 (Rust backend)
Building the core requires `AnkiCore.xcframework` from the upstream `anki` rslib (Rust toolchain +
iOS targets). The workflow will gain a Rust build step then. Until M2, the app builds and runs
against the in-memory collection stub.
