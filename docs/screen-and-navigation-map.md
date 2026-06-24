# Screen & Navigation Map

## Android (observed) → iOS

| Android screen / entry | iOS screen | Status |
|---|---|---|
| `DeckPicker` (deck list, + FAB, AI creator FAB, Insights) | `DeckListView` (List + creator toolbar button) | ◑ list+creator; counts M2 |
| `ReviewerFragment` (question/answer, Ask Claude, overlay buttons) | `ReviewerView` (MathJax WebView, Show Answer, Ask Claude) | ◑ render+chat; answer buttons M2 |
| `AiChatBottomSheetFragment` (`fragment_ai_chat.xml`) | `ChatView` (sheet) | ✅ |
| AI Card Creator (merged into chat fragment, creator mode) | `ChatView(cardId: -1)` creator sheet from decks | ✅ |
| `AiInsightsDashboardActivity/Fragment` | `InsightsView` | ◑ engine; live stats M2 |
| `AiSettingsFragment` (API key, model, test, budget) | `AISettingsView` | ✅ + Keychain |
| `ForcedStudySettingsFragment` + overlays | M3 (constrained) | ☐ |
| Card browser / editor / stats / preferences / sync | M2 | ☐ |

## Navigation shell
`RootView` = `TabView` { Decks, Insights, Settings }. Chats present as sheets in a
`NavigationStack`. Reviewer pushes from a deck. This mirrors the Android entry points while
following iOS navigation idioms (DL-002).

## Flows implemented (M1)
- Decks → tap deck → Reviewer → Show Answer → **Ask Claude** → chat → (edit/add proposal → approve).
- Decks → **Create Cards with AI** → describe → generated proposals → **Add to deck**.
- Settings → enter key (Keychain) → **Test connection** → budget/spend.
