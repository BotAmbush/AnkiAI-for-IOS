# iOS Architecture

## Layering

```
SwiftUI Views (Features/*, App/*)
        │  observe
ViewModels (@MainActor ObservableObject)   ── AIChatViewModel, …
        │  call
Domain services / gateways
   ├─ CollectionGateway  ──► PRODUCTION: BackendCollectionGateway (actor)
   │        │                              └─► AnkiCollection (C-ABI) ──► AnkiCore.xcframework (Rust anki 25.09.2)
   │        └─► StubCollectionGateway (previews / isolated unit tests only)
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

## Rust backend (implemented for M2.1)
- `tools/build-anki-backend.sh` clones pinned `anki` (submodule-aware), builds the
  narrow C-ABI bridge crate `rust/anki-backend-ios` (staticlib) for
  `aarch64-apple-ios` + `aarch64-apple-ios-sim`, and assembles
  `Frameworks/AnkiCore.xcframework` (CI; no cache; reproducible).
- The bridge exposes a tiny C surface (open / deck_tree_json / close / create_fixture
  / last_error / string_free) — **no raw Rust types cross the boundary**. Header +
  `module AnkiCore` modulemap ship in the xcframework; Swift does `import AnkiCore`.
- `AnkiCollection` (Swift) owns the opaque handle (open in init, close once);
  `BackendCollectionGateway` (actor) serializes access behind `CollectionGateway`.
- Build-script notes (root causes fixed): clone submodules (i18n `.ftl`); enable
  `tokio/io-util` via the bridge (anki omits it); build `anki_proto` first
  (descriptor race); no cargo cache (cross-target poisoning).
- Read path done (deck tree). Scheduler/FSRS/notes/sync remain to be surfaced via
  the same xcframework in later slices — they guarantee parity (DL-001).

## Persistence split
- **Anki collection** (`collection.anki2`): owned exclusively by the Rust backend (M2). Never opened by Swift SQLite.
- **AI database** (`ai_insights.db`): owned by `AIDatabase` over `SQLiteDatabase`. Holds only `ai_*` tables. Mirrors the Android "separate database" invariant.

## Rendering
`CardWebView` (UIViewRepresentable over WKWebView) renders raw Anki card HTML with
MathJax configured for `\( \)` / `\[ \]`, transparent background, dark-mode CSS, and
native `dir`-based RTL. Template/CSS-driven rendering (qfmt/afmt) comes from the
backend `render_card` at M2; M1 renders fields/proposals directly.
