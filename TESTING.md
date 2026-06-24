# Testing

Tests run on the iOS Simulator via `xcodebuild test` (locally on a Mac or in CI). They require no
device, no network, and no API key — network and collection are faked.

## Suites (`AnkiAITests/`)
- `ClaudeAPIClientTests` — request shaping, `x-api-key`/version headers, **prompt-caching** header +
  `system` array breakpoint, image content blocks, usage parsing, 401/529 mapping (fake transport).
- `AIResponseParserTests` — edit/add-card action parsing, creator JSON array, fenced-block
  extraction, malformed-JSON → plain-text fallback, `front_html`/`front` preference, deck default.
- `HTMLTextTests` — `stripHtml`, math-aware strip (`\(\)`, `\[\]`, `<anki-mathjax>`), Hebrew preserved.
- `PricingAndTipsTests` — Haiku/Sonnet cost math, error strings, tip-engine top-5 + priority sort.
- `AIDatabaseTests` — `ai_chat_messages` insert/fetch ordering, session delete, metadata round-trip
  (in-memory SQLite).
- `AIChatViewModelTests` — reviewer plain reply persistence, system prompt carries card context,
  edit proposal surfaced + applied (note updated), creator proposal parsing + caching suffix, spend
  tracked, error surfaced (fake client + stub gateway).

## Mapped to CLAUDE.md testing requirements
| Requirement | Where | Status |
|---|---|---|
| database reads/writes | `AIDatabaseTests` | ✅ |
| HTML sanitization/preservation | `HTMLTextTests` | ✅ |
| MathJax content | `HTMLTextTests` (markers), renderer | ✅ / manual |
| Hebrew / bidi text | `HTMLTextTests`, VM context test | ✅ |
| AI response parsing | `AIResponseParserTests` | ✅ |
| malformed AI responses | `AIResponseParserTests` | ✅ |
| network errors | `ClaudeAPIClientTests`, VM error test | ✅ |
| Keychain credential handling | `AISettingsStore` (manual; CI sim has Keychain) | ◑ |
| migrations / scheduling / FSRS / timezone / import-export round trips | M2 (backend) | ☐ |
| feature parity regressions | parity checklist + VM tests | ◑ |

## Running
```bash
xcodebuild -project AnkiAI.xcodeproj -scheme AnkiAI \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -resultBundlePath build/TestResults.xcresult test
```
CI uploads `TestResults.xcresult` under the `diagnostics` artifact.
