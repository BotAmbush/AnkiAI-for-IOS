# Decision Log

## DL-001 — Reuse the upstream Rust `anki` backend for the core engine
**Date:** 2026-06-24 · **Status:** Accepted

**Context.** AnkiDroid does not implement the scheduler, FSRS, sync, database format, or import/export in Kotlin. Those live in the upstream **Rust `anki` library** (`rslib`), shipped to Android as `anki-android-backend` (rsdroid) and called through a thin Kotlin `libanki` wrapper over a protobuf interface. CLAUDE.md requires *collection database compatibility, scheduling, FSRS, sync, and import/export parity*.

**Decision.** The iOS app will reuse the **same Rust `anki` backend**, compiled as an `xcframework` for iOS, wrapped by a Swift `libanki`-equivalent — mirroring how official AnkiMobile is built. We will **not** reimplement the scheduler/FSRS/sync in Swift.

**Why.** (1) Data-format and sync compatibility are non-negotiable and the Rust backend is the canonical implementation. (2) A Swift reimplementation would be enormous and would risk silent data corruption. (3) The fork itself leaves the Anki core untouched — parity means matching that.

**Consequences.** Requires a Rust toolchain + macOS in CI to build the xcframework (milestone 2). Until then, the app runs against an in-memory `StubCollectionGateway` so the native AI layer and UI can ship and be tested first.

## DL-002 — Native Swift/SwiftUI, no cross-platform runtime
**Date:** 2026-06-24 · **Status:** Accepted
Per CLAUDE.md: Swift + SwiftUI (UIKit/WKWebView where needed), async/await, Keychain. No React Native / Flutter / KMP-UI / Compose / web wrapper. Business logic ported conceptually, not line-by-line.

## DL-003 — `CollectionGateway` abstraction between AI features and the collection
**Date:** 2026-06-24 · **Status:** Accepted
The AI layer touches the collection only through a small `CollectionGateway` protocol (decks, note read/update, add note, card context). This makes the AI features unit-testable today and lets the Rust-backed implementation drop in at M2 without UI changes.

## DL-004 — iOS deployment target 16.0
**Date:** 2026-06-24 · **Status:** Accepted
Android `minSdk = 24` (Android 7, ~99% of devices). iOS analog chosen as **16.0**: modern SwiftUI (`NavigationStack`, `.task`, vertical-axis `TextField`) with very broad device coverage. Revisit only if a required API forces a bump; do not raise silently.

## DL-005 — API key in Keychain (upgrade over Android SharedPreferences)
**Date:** 2026-06-24 · **Status:** Accepted
The Android fork stores the Claude key in `SharedPreferences`. iOS stores it in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Non-secret prefs (budget, spend) stay in `UserDefaults`.

## DL-006 — XcodeGen for deterministic project generation
**Date:** 2026-06-24 · **Status:** Accepted
`project.yml` is the source of truth; CI regenerates `AnkiAI.xcodeproj` with `xcodegen generate`. The generated `.pbxproj` is git-ignored to avoid fragile hand-edits. Xcode can still open the generated project locally.

## DL-007 — Preserve the fork's model choices
**Date:** 2026-06-24 · **Status:** Accepted
Reviewer chat → `claude-haiku-4-5-20251001`; card creator → `claude-sonnet-4-6` (matches the Android fork). Pricing constants ported with them. Models are user-relevant cost/quality trade-offs; keep parity rather than silently changing them.

## DL-008 — Bundle MathJax locally (planned, M1 tail)
**Date:** 2026-06-24 · **Status:** Proposed
Card rendering currently loads MathJax v3 from a CDN. For offline parity with AnkiDroid (which bundles MathJax), switch to a bundled copy. Tracked in progress.md.
