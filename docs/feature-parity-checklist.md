# Feature Parity Checklist

Legend: ✅ complete · ◑ partial · ☐ not started · 🔬 needs Rust backend (M2)

A feature is **not** marked complete just because a similarly-named Swift file exists
(per CLAUDE.md). "Complete" means implemented **and** tested or rendered end-to-end.

## Core Anki (backend-backed → M2)

| Feature | Status | Notes |
|---|---|---|
| Collection open/close | 🔬 ☐ | Rust backend xcframework (DL-001) |
| Decks & subdecks | 🔬 ◑ | Names/hierarchy modeled; live counts need backend |
| Notes / cards / note types | 🔬 ◑ | `NoteData` + gateway; real CRUD at M2 |
| Card templates & CSS | 🔬 ☐ | Template rendering is backend `render_card` |
| Front/back & HTML rendering | ◑ | `CardWebView` renders raw HTML now; template/qfmt via backend |
| MathJax rendering | ✅ | WKWebView + `\( \)`/`\[ \]`; bundle locally (M1 tail) |
| Hebrew / RTL | ✅ | `dir` preserved end-to-end; strip helpers tested |
| Mixed RTL/LTR | ✅ | per-span `dir` honored |
| Cloze cards | 🔬 ☐ | backend cloze rendering |
| Media (image/audio) | 🔬 ☐ | backend media DB + file store (M2) |
| Card browser | 🔬 ☐ | M2 |
| Note/card editing | ◑ | AI edit-proposal path works on stub; full editor M2 |
| Review screen | ◑ | reviewer renders + Ask Claude; queue/answer buttons M2 |
| Answer buttons | 🔬 ☐ | backend `answerCard` |
| Undo / bury / suspend / flags / tags | 🔬 ☐ | backend ops (M2) |
| Filtered decks / custom study | 🔬 ☐ | M2 |
| Statistics | 🔬 ☐ | backend stats (M2) |
| Scheduling / learning-review-relearn steps | 🔬 ☐ | backend scheduler (M2) |
| FSRS behavior & config | 🔬 ☐ | backend FSRS (M2) |
| Timezone / day-rollover | 🔬 ☐ | backend + tests (M2) |
| Collection DB compatibility | 🔬 ☐ | guaranteed by reusing backend |
| Import/export (.apkg, colpkg) | 🔬 ☐ | backend import/export (M2) |
| Backups & restoration | 🔬 ☐ | backend backups (M2) |
| Synchronization / AnkiWeb | 🔬 ☐ | backend sync (M2) |
| Settings/preferences | ◑ | AI settings ✅; collection prefs M2 |
| Notifications / reminders | ☐ | M3 |
| Background tasks | ☐ | M3 (iOS-constrained) |
| Sharing / file opening (.apkg) | ☐ | M2/M3 |
| Accessibility | ☐ | M3 |
| Dark mode | ◑ | SwiftUI + WebView dark CSS; audit M3 |
| Localization (incl. Hebrew) | ☐ | strings exist in fork; wire M1 tail/M3 |

## Custom AI features (this fork)

| Feature | Status | Notes |
|---|---|---|
| Claude API client (caching, images, usage) | ✅ | tested |
| Provider abstraction | ✅ | `AIChatAPIClient` |
| Prompt management (reviewer + creator, RTL/MathJax rules) | ✅ | verbatim port, tested |
| Ask-Claude reviewer chat | ✅ | VM tested; UI wired |
| Edit-card proposal + apply | ✅ | tested incl. note update |
| Add-card proposal (reviewer) | ✅ | tested |
| AI card creator (generate → review → add) | ✅ | VM tested; UI sheet |
| Creator image/PDF attachments | ☐ | client supports images; picker M1 tail/M3 |
| AI-generated HTML validation/insertion | ✅ | raw-HTML insertion path + parsing tested |
| MathJax produced by AI | ✅ | renderer honors enforced delimiters |
| AI insights / tip engine | ✅ (engine) / 🔬 (live stats) | engine tested; revlog reads M2 |
| Forced study mode | ☐ | M3, partial parity (iOS limits) |
| Scheduler hint overlay | ☐ | M3 |
| Upstream update checker | ☐ | optional |
| API-key storage | ✅ | Keychain (upgrade) |
| Budget / spend tracking | ✅ | tested |
| Error handling (network/401/429/529) | ✅ | tested |
| Chat persistence (separate ai db) | ✅ | tested |
