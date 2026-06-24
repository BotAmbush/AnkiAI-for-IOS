# Third-Party Notices

AnkiAI for iOS is a derivative of AnkiDroid and its AI fork. Attributions:

## Derived source
- **AnkiDroid** — https://github.com/ankidroid/Anki-Android — GPL-3.0. Domain concepts, feature
  set, and the AI-layer behavior ported here originate from AnkiDroid and the
  `BotAmbush/Anki-Android-AI` fork. Origin is disclosed, not concealed.

## Runtime components shipped in the app
- **MathJax** — https://github.com/mathjax/MathJax — Apache-2.0. Used to render LaTeX in cards
  (planned to be bundled locally; currently loaded from CDN — see decision-log DL-008).
- **Apple system frameworks** (SwiftUI, UIKit, WebKit, Security/Keychain, libsqlite3) — Apple SDK
  license. The AI database uses the OS-provided SQLite; no third-party SQLite library is bundled.

## Planned (milestone 2)
- **Anki Rust backend (`rslib`)** — https://github.com/ankitects/anki — AGPL-3.0. To be compiled as
  `AnkiCore.xcframework` for collection/scheduler/FSRS/sync/import-export. AGPL distribution
  obligations are tracked as a release blocker in `docs/licensing-analysis.md`.

## Build-time only (not shipped)
- **XcodeGen** — https://github.com/yonaskolb/XcodeGen — MIT. Generates the Xcode project from
  `project.yml`.

## Service
- **Anthropic Claude API** — https://www.anthropic.com/api — no bundled code; users supply a key,
  usage billed by Anthropic.

No third-party Swift packages are currently bundled. Any future dependency will be added here with
its license before use.
