# AI Feature Analysis (the unique value of this fork)

Source: `AnkiDroid/src/main/java/com/ichi2/anki/ai/**` plus integration points in
`DeckPicker.kt`, `ReviewerFragment.kt`, `preferences/Preferences.kt`.

## Modules & Android sources → iOS mapping

| Android file | Purpose | iOS port | Status |
|---|---|---|---|
| `ai/api/ClaudeApiClient.kt` | Anthropic Messages API, prompt caching, images, usage | `AI/Provider/ClaudeAPIClient.swift` | ✅ ported + tested |
| `ai/api/LlmApiClient.kt` | Provider interface | `AIChatAPIClient` protocol | ✅ |
| `ai/chat/AiChatViewModel.kt` | Reviewer + creator logic, proposals, spend | `AI/Chat/AIChatViewModel.swift` | ✅ ported + tested |
| `ai/chat/AiCardCreatorStaticPrompt.kt` | Creator system prompt | `AI/Prompts.swift` | ✅ verbatim |
| `ai/chat/AiChatMessage.kt` / `AiChatDao.kt` | Chat persistence | `AI/Chat/AIChatMessage.swift` + `Persistence/AIDatabase.swift` | ✅ ported + tested |
| `ai/chat/AiChatBottomSheetFragment.kt` / `ChatMessageAdapter.kt` | Chat UI | `Features/Chat/ChatView.swift` | ✅ SwiftUI |
| `ai/insights/AiTipEngine.kt` | Study-pattern tips | `AI/Insights/AITipEngine.swift` | ✅ ported + tested |
| `ai/insights/AiInsightsDashboard*` | Insights screen | `Features/Insights/InsightsView.swift` | ◑ UI done; live stats need backend |
| `ai/insights/StudyInsightsViewModel.kt` | Reads revlog, writes ai_* | pending (`RevlogAnalyzer` needs backend) | ☐ M2 |
| `ai/analytics/RevlogAnalyzer.kt` | READ-ONLY revlog/cards queries | needs collection (`CollectionGateway` extension) | ☐ M2 |
| `ai/data/AiDatabase.kt` + DAOs/entities | Separate `ai_insights.db` | `Persistence/AIDatabase.swift` | ◑ chat table done; card-meta/study-log tables pending |
| `ai/settings/AiSettingsFragment.kt` | API key, model, test | `Features/Settings/AISettingsView.swift` | ✅ + Keychain |
| `ai/enforcement/*` (ForcedStudy service/alarm/boot/overlay, AiChatLauncherActivity) | Forced study mode | iOS analog (constrained) | ☐ M3 — see migration-risks |
| `ai/hints/SchedulerHintOverlay.kt` | Display-only overlay | trivial; M3 | ☐ |
| `ai/update/UpstreamUpdateChecker.kt` / `UpstreamCheckWorker.kt` | GitHub release check | optional; low priority | ☐ |

## Behavioural details preserved in the port

- **Two models**: reviewer chat = Haiku 4.5; creator = Sonnet 4.6. Pricing constants ported (`AIPricing`).
- **Prompt caching**: when a dynamic suffix exists, the static system block gets `cache_control: ephemeral` + `anthropic-beta: prompt-caching-2024-07-31`; the deck list / per-request context follows uncached. Verified by `ClaudeAPIClientTests`.
- **Card HTML rules**: allowed tags `<div><span><b><br><hr><code>`; forbidden `<anki-mathjax>`, JS, external CSS/fonts, flex/grid/tables; units kept outside `\( \)` / `\[ \]`.
- **RTL/Hebrew**: prompts mandate `dir="rtl"`/`dir="ltr"`; card HTML carries its own `dir`; rendering via WKWebView preserves it. `mathAwareStripHtml` keeps formulas as `[math: …]` for the model.
- **MathJax delimiters**: only `\( \)` (inline) and `\[ \]` (block). Renderer (`CardWebView`) configures MathJax with exactly these.
- **JSON action protocol** (reviewer): `{"action":"edit_card",…}` and `{"action":"add_card",…}`; creator returns a JSON array. Extraction handles bare JSON and ```json fenced blocks. Malformed JSON degrades to plain text (parity with the Kotlin `runCatching` fallback).
- **Deck resolution** for generated cards: exact (case-insensitive) → `::suffix` → contains → first deck → id 1. Ported in `resolveDeckId`.
- **Spend tracking**: per-call token usage → USD, accumulated in `UserDefaults` (`ai_total_spent_usd`), budget default $20.
- **Error mapping**: no-internet / 401 / 429 / 529-overloaded / generic, surfaced as the same user strings.

## Gaps / deferred
- Image & PDF attachments in the creator (camera/photos/PDF → base64) — model + client support images already; the SwiftUI attachment picker + `PdfRenderer` analog (PDFKit) is M1 tail / M3.
- `ai_card_meta` and `ai_study_log` tables + `StudyInsightsViewModel` writes — M2 (needs revlog reads).
- Forced-study enforcement — M3; iOS cannot replicate Android's `TYPE_APPLICATION_OVERLAY` / always-on foreground service, so the design will use notifications + an in-app enforced session. Documented as a partial-parity item.
