# iOS Architecture

## Layering

```
SwiftUI Views (Features/*, App/*)
        │  observe
ViewModels (@MainActor ObservableObject)   ── AIChatViewModel, …
        │  call
Domain services / gateways
   ├─ CollectionGateway  ──► M1: StubCollectionGateway (in-memory)
   │                         M2: BackendCollectionGateway ──► Swift libanki ──► Rust anki xcframework
   ├─ AI Provider (AIChatAPIClient → ClaudeAPIClient)  ──► Anthropic API (URLSession)
   ├─ AIDatabase (ai_insights.db)  ──► SQLiteDatabase (system libsqlite3)
   └─ AISettingsStore  ──► Keychain (secrets) + UserDefaults (prefs)
```

Boundaries map to the directories under `AnkiAI/`:
`App` (lifecycle/navigation) · `Features` (UI) · `Domain` (models + gateway) ·
`AI` (provider, chat, prompts, insights) · `Persistence` (SQLite + AI db) ·
`Security` (Keychain) · `Rendering` (WKWebView card view).

## Principles (per CLAUDE.md)
- No giant views: each screen is a small `View` + a focused VM.
- No global mutable state: dependencies flow from `AppEnvironment` (injected via `@EnvironmentObject`).
- No direct API calls from views: views call VMs; VMs call the provider/gateway.
- Testable without a device: VMs take injected fakes (`FakeChatClient`, `FakeTransport`, `StubCollectionGateway`, in-memory `AIDatabase`).
- Swift concurrency: `async/await` throughout; `@MainActor` on VMs; gateway is an `actor`.

## The CollectionGateway seam (DL-003)
The AI features need only a handful of collection operations. `CollectionGateway`
exposes exactly those (decks, note read/update, add note, card context, notetypes).
M1 ships an in-memory stub so the whole app + AI flow runs and is tested on CI/Simulator.
M2 implements `BackendCollectionGateway` over the Rust backend with identical semantics.

## Rust backend plan (M2)
- Build `anki` `rslib` for `aarch64-apple-ios` + `aarch64-apple-ios-sim` (+ `x86_64` sim) → `AnkiCore.xcframework` in CI.
- Bridge via the backend's protobuf service (the same surface `libanki` uses on Android) or uniffi.
- Swift `libanki`-equivalent mirrors the Kotlin `Collection`, `Decks`, `Notes`, `Cards`, `Notetypes`, `Scheduler`, `Media`, import/export, sync.
- This is what guarantees collection/scheduler/FSRS/sync/import-export parity (DL-001).

## Persistence split
- **Anki collection** (`collection.anki2`): owned exclusively by the Rust backend (M2). Never opened by Swift SQLite.
- **AI database** (`ai_insights.db`): owned by `AIDatabase` over `SQLiteDatabase`. Holds only `ai_*` tables. Mirrors the Android "separate database" invariant.

## Rendering
`CardWebView` (UIViewRepresentable over WKWebView) renders raw Anki card HTML with
MathJax configured for `\( \)` / `\[ \]`, transparent background, dark-mode CSS, and
native `dir`-based RTL. Template/CSS-driven rendering (qfmt/afmt) comes from the
backend `render_card` at M2; M1 renders fields/proposals directly.
