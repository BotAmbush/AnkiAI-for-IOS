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

## Anki Rust backend (`AnkiCore.xcframework`) — required since M2.1

The app links the canonical upstream Anki Rust backend (pinned in
`docs/anki-backend-pin.md`: `ankitects/anki` `25.09.2`, commit `3890e12c…`, Rust 1.89.0).

Build it locally on a Mac (needs `rustup` + `protoc`):
```bash
brew install protobuf
tools/build-anki-backend.sh xcframework   # → Frameworks/AnkiCore.xcframework
xcodegen generate
```
`tools/build-anki-backend.sh spike` just compiles the bridge for both iOS targets
(`aarch64-apple-ios`, `aarch64-apple-ios-sim`) without assembling the xcframework.

The script clones anki **with submodules** (i18n translations), builds `anki_proto` first
(to avoid a build-script descriptor race), then the bridge crate
(`rust/anki-backend-ios`), and assembles the xcframework. It is **cache-free and
reproducible**.

### CI modes (`workflow_dispatch` input `mode`)
- `full` — build the xcframework, then app + unit + integration tests + unsigned IPA.
- `backend_spike` — only prove the backend compiles for iOS.
- `backend_xcframework` — only build the xcframework.

The `app` job downloads the `AnkiCore-xcframework` artifact before generating the project,
so `Frameworks/AnkiCore.xcframework` exists for XcodeGen and `xcodebuild`.
