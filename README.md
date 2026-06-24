# AnkiAI for iOS

A native **Swift / SwiftUI** port of [AnkiAI](https://github.com/BotAmbush/Anki-Android-AI) —
an AnkiDroid fork that integrates **Claude** (Anthropic) into the flashcard workflow — staying
compatible with AnkiWeb sync and Anki Desktop.

> **Status: early, honest, milestoned.** The native AI layer, app shell, tests, and macOS CI are
> built. The Anki core (collection, scheduler, FSRS, sync, import/export) is delivered by reusing
> the upstream **Rust `anki` backend** compiled for iOS — that is milestone 2 and is not done yet.
> See [`docs/known-issues.md`](docs/known-issues.md) and [`docs/progress.md`](docs/progress.md).
> No claim that the app compiles or that an IPA exists is made until the macOS workflow runs green.

## What works today (M1)
- Native **Claude API client** (prompt caching, images, usage/cost, error mapping) — tested.
- **Ask Claude** reviewer chat with edit / add-card proposals; **AI Card Creator**.
- Anki-style **HTML + MathJax** rendering with full **Hebrew / RTL** support (WKWebView).
- **AI Insights** tip engine; **Keychain**-stored API key; budget/spend tracking.
- A separate **`ai_insights.db`** (system SQLite) for chat history — never mixed with the collection.
- Runs end-to-end on an in-memory collection stub so the UI + AI flow are exercised on Simulator.

## Architecture
SwiftUI + `@MainActor` view models + an injectable `CollectionGateway` seam in front of the
collection. The Rust `anki` backend slots in behind that gateway at M2 (DL-001).
See [`docs/ios-architecture.md`](docs/ios-architecture.md) and [`docs/decision-log.md`](docs/decision-log.md).

## Build
Local dev is on Windows, which cannot run Xcode. The authoritative build is **GitHub Actions on
macOS** (`.github/workflows/ios.yml`, `workflow_dispatch`): regenerate project with XcodeGen →
build for a generic iOS device (unsigned) → run unit tests on Simulator → package
`AnkiAI-unsigned.ipa` → upload IPA + logs + dSYMs. See [`BUILDING.md`](BUILDING.md).

To open locally on a Mac:
```bash
brew install xcodegen
xcodegen generate
open AnkiAI.xcodeproj
```

## Install (unsigned IPA)
Sign + install the artifact on-device with iLoader — see [`INSTALLING-IPA.md`](INSTALLING-IPA.md).

## License
**GPL-3.0**, inherited from AnkiDroid. The Rust `anki` backend (M2) is AGPL-3.0 — see
[`docs/licensing-analysis.md`](docs/licensing-analysis.md), [`LICENSES.md`](LICENSES.md),
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

API usage is billed by Anthropic; bring your own key (stored in the Keychain, never committed).
