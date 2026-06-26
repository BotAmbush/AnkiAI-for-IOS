**Audit Scope**
Reviewed iOS commit `a44e25198b2e3c6bc59b655759ab26603485ca15` and Android reference `522838f52166a7a8e6a3143c5770fb5746aa1dab` in the disposable folders only. I did not modify source, build, commit, push, or touch the original repos. The iOS working tree has a pre-existing modified `CLAUDE-REPAIR-REPORT.md`; production source is otherwise at the requested commit.

**Prior Findings**
| Prior finding | Status | Evidence |
|---|---:|---|
| P0 seeded/demo collection can replace AnkiWeb | FIXED | Provenance defaults safe/seeded in `AnkiAI/App/AppEnvironment.swift:32-40`; upload forbidden for seeded/unknown in `AnkiAI/Security/KeychainStore.swift:152-165`; UI blocks upload in `AnkiAI/Features/Settings/AISettingsView.swift:102-110`. |
| Full-upload provenance, backup, destructive confirmation | PARTIALLY FIXED | UI has destructive confirmation and backup before upload at `AISettingsView.swift:206-214`, `300-318`; however media sync after upload is silently ignored with `try?` at `AISettingsView.swift:315`. |
| Full download, two-way sync, media sync, conflict handling, rollback | PARTIALLY FIXED / CANNOT FULLY VERIFY WITHOUT DEVICE | Backend has full-download temp/integrity/atomic claim and endpoint discovery at `rust/anki-backend-ios/src/lib.rs:1499-1635`; full-sync-required is surfaced at `AISettingsView.swift:262-281`; media errors are surfaced for normal/download sync at `AISettingsView.swift:273-291`. Real AnkiWeb behavior still depends on device/network validation. |
| APKG import/export | PARTIALLY FIXED | Export test only at `AnkiAITests/BackendImportExportTests.swift:4-34`; APKG import happy path explicitly unasserted at lines `7-12`; safety tests cover malformed/missing only at `BackendApkgImportSafetyTests.swift:17-45`. |
| Background-sync error handling | FIXED | Result persistence at `AnkiAI/Platform/BackgroundSync.swift:25-50`; surfaced in settings at `AISettingsView.swift:92-97`. Scheduling submit still uses benign best-effort `try?` at `BackgroundSync.swift:11-16`. |
| Bulk-operation silent try?/partial failure | FIXED | Bulk loop counts success/failure and keeps selection on partial failure at `AnkiAI/Features/Browser/CardBrowserView.swift:139-165`. |
| AI Insights revlog parity | PARTIALLY FIXED | Uses graph/search data at `AnkiAI/Features/Insights/InsightsView.swift:61-84`, but still uses default retention `0.85` when no 30-day reviews exist at line `67`, and average ease/per-deck retention remain uncomputed at lines `77-82`. |
| Forced-study classification | FIXED | Feature map classifies as partial/platform-limited; implementation is iOS notification + in-app session, not Android overlay. Evidence in `docs/android-ios-feature-map.yml` forced-study notes and `AnkiAI/Platform/ForcedStudyManager.swift`. |
| Small fixtures/mocks/offline-only tests | PARTIALLY FIXED | 192 test functions exist, including large fixture tests. Still no live AnkiWeb/APKG happy-path import/device tests in source. |

**Latest AI/UX Repairs**
| Area | Status | Evidence |
|---|---:|---|
| A. Hierarchical deck picker | PARTIALLY FIXED | Picker is searchable and shows leaf + parent path at `DeckPickerSheet.swift:20-24`, `40-71`; Manual Add uses real decks and selected `deckId` at `ManualAddCardView.swift:54-76`, `93-106`. Not fully fixed for AI creator: creator has no deck picker and defaults to first deck when no explicit default is passed at `AIChatViewModel.swift:285-303`. Selected deck is not persisted beyond the view state. |
| B. AI language + RTL | MOSTLY FIXED | Automatic/Hebrew/English and prompt instruction at `AILanguage.swift:4-33`; persisted globally at `KeychainStore.swift:146-150`; injected into reviewer/creator prompts at `Prompts.swift:63-68`, `147-156`; semantic RTL detection at `AILanguage.swift:36-65`; chat/input alignment at `ChatView.swift:22-24`, `143-148`, `192-210`. |
| C. Creator-session persistence | PARTIALLY FIXED | Messages, draft, language, proposals, parse failure, raw response and attachments persist at `AIChatViewModel.swift:83-111`. Missing/weak: model is fixed, not persisted (`ClaudeAPIClient.swift:123-124`); `repairAttempted` and `lastAllDecks` are not persisted; large attachments are stored inline as base64 in JSON at `CreatorSessionStore.swift:3-15`, `25-28`. |
| D. Markdown rendering | FIXED WITH KNOWN LIMITATION | Safe subset parser at `ChatMarkdown.swift:15-89`; assistant renderer at `ChatView.swift:207-210`; no WebView/HTML execution in chat. MathJax inside chat messages is intentionally not rendered; prompt says chat math is plain text at `Prompts.swift:80-84`. |
| E. Card-response parsing/recovery | PARTIALLY FIXED | Handles arrays, `{cards}`, fenced JSON, BOM, prose slices, Hebrew/MathJax strings, and partial invalid cards at `AIModels.swift:152-205`. Local retry/repair/regenerate UI exists at `ChatView.swift:277-290`. Duplicate accepted-card prevention is not implemented: adding removes current proposal only at `AIChatViewModel.swift:385-395`; regeneration clears proposals and can recreate already accepted content at `AIChatViewModel.swift:285-291`, `347-350`. |
| F. AI toolbar/session visibility | PARTIALLY FIXED | Language/pending/attachment count visible at `ChatView.swift:96-108`; clear/language menu at `ChatView.swift:81-95`. Model is not visible; retry state is only visible on parse failure; attachment count is local UI state and is not restored from persisted `lastAttachments`. |

**Findings**

**P1 - AI creator deck selection is not wired to the new deck picker**
Evidence: `DeckPickerSheet` exists and Manual Add uses it, but `ChatView` has no creator deck picker; creator generation uses `defaultDeckName: ""` and falls back to `allDecks.first` at `AIChatViewModel.swift:285-303`. Production card creation then adds to whatever deck the model emitted/resolved at `AIChatViewModel.swift:365-382`, `385-395`.
Consequence: AI-created cards can still land in the wrong deck, especially for same-leaf-name decks or when the model omits/guesses a deck.
Correction: add a persisted creator selected-deck id/path, use `DeckPickerSheet` in creator UI, pass it as `defaultDeckName`, and add cards by selected real deck unless the user explicitly changes it.
Blocks RC: Yes, for the latest AI/UX repair quality.

**P1 - APKG import remains incomplete**
Evidence: APKG happy-path import is explicitly not asserted in `AnkiAITests/BackendImportExportTests.swift:7-12`; only malformed/missing failure preservation is tested in `BackendApkgImportSafetyTests.swift:17-45`. Production still exposes `importApkg` at `BackendCollectionGateway.swift:105-115`.
Consequence: Android parity for APKG import/export is not complete; user APKG imports may fail.
Correction: fix the backend deck-kind import issue and add a real export-to-fresh-import round-trip test with notes, decks, media, and scheduling.
Blocks RC: Yes for full migration parity; no if APKG import is declared a release limitation.

**P1 - Creator persistence stores large/private attachments inline and misses retry state**
Evidence: attachments are persisted as base64 fields in `CreatorSessionStore.swift:3-15`, `25-28`; VM writes restored attachments inline at `AIChatViewModel.swift:91`, `100-110`. `repairAttempted` and `lastAllDecks` are private state but are not in the persisted snapshot (`AIChatViewModel.swift:37-42`, `83-111`).
Consequence: large/sensitive attachment content can bloat or linger in app support JSON; after relaunch, repair/local parse can lose deck resolution context and UI attachment count does not reflect restored attachments.
Correction: store attachments as scoped files with metadata, size limits, and cleanup; persist retry/repair state and deck list or re-resolve decks before retry/repair.
Blocks RC: Yes for the creator-session repair claim.

**P2 - Parsing/regeneration can duplicate accepted cards**
Evidence: accepted proposals are removed locally after add at `AIChatViewModel.swift:392-395`, but there is no accepted-content/id ledger. Regeneration reuses the original prompt and clears proposals at `AIChatViewModel.swift:285-291`, `347-350`.
Consequence: a user can accept a card, regenerate/repair similar output, and add duplicates.
Correction: track accepted proposal fingerprints per session and suppress/warn on duplicate front/back/deck before add.
Blocks RC: No, but should be fixed before broad real-collection use.

**P2 - AI Insights still shows derived confidence from fallback data**
Evidence: if there are no 30-day reviews, retention defaults to `0.85` at `InsightsView.swift:67`, which can feed a positive retention tip through `AITipEngine.swift:75-82`.
Consequence: users with sparse/no revlog data may see misleading “85% retention” style advice.
Correction: represent missing retention as nil and suppress retention tips until real data exists.
Blocks RC: No, but it keeps AI Insights partial.

**P2 - Status/docs contain stale or contradictory completion claims**
Evidence: `docs/feature-parity-checklist.md` still has early M2 partial/stub statuses, while `docs/android-ios-feature-map.yml` marks `synchronization` status as `completed` but notes “Reverted to partial” in the same entry around the synchronization notes. `CODEX-INDEPENDENT-AUDIT.md` is only a prior blocked-session note, not the previous substantive audit.
Consequence: reviewers can over-trust completion metadata.
Correction: reconcile docs to one authoritative Mode-A partial status and remove stale milestone-era checklist rows.
Blocks RC: No, but blocks confident finalization.

**IPA / CI Evidence**
The local IPA exists at `AnkiAI-unsigned.ipa`, size `7,418,531` bytes. Extracted IPA contains `Payload/AnkiAI.app/AnkiAI` with Mach-O magic `CF FA ED FE` and CPU type bytes for arm64; executable size is `22,060,632` bytes. `Info.plist` is compiled binary plist and includes `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`, `UIBackgroundModes`, `BGTaskSchedulerPermittedIdentifiers`, and `arm64`. No embedded `.mobileprovision`, test bundle, framework, or obvious test payload was present. MathJax resource is bundled as `tex-mml-svg.js`.
The repo defines exactly 192 `func test...` methods across 51 XCTest classes. CI workflow runs build, simulator tests, packages unsigned IPA, and verifies file-sharing plist keys at `.github/workflows/ios.yml:115-172`. I did not independently query GitHub Actions; local evidence matches the reported 192-test claim but not the live run result.

**Safety Answers**
- Safe with a real collection when an external backup exists: cautiously yes for normal use, but APKG import and AI creator persistence remain partial.
- Normal two-way sync reasonably safe: yes, with device validation already reported but not independently reproduced here.
- Full download reasonably safe: likely yes by backend design, but still device/network dependent.
- Full upload blocked when provenance unsafe: yes through production UI.
- Can parsing/retry create duplicate cards: yes.
- Can clearing a creator session delete accepted cards: no evidence of that; `clearSession` only clears AI DB/session state at `AIChatViewModel.swift:419-433`.
- Can attachment persistence leak or orphan sensitive files: yes, because attachment payloads are stored inline in session JSON.
- Can Markdown rendering execute unsafe content: no evidence; chat uses SwiftUI `Text`/`AttributedString`, not WebView HTML/script. MathJax is not rendered inside chat.

**Percentages**
Core Anki functionality: 82%  
Sync safety: 78%  
Import/export: 55%  
Backup/restore: 78%  
AI functionality: 72%  
Automated-test confidence: 68%  
Latest AI/UX repair quality: 63%  
Physical-device validation: 45%  
Overall migration completeness: 72%

P0 remaining: no confirmed P0 remains.  
P1 remaining: yes.  
Another Claude repair pass needed: yes.

Smallest ordered remaining work list:
1. Wire a persisted real deck picker into AI creator and use it for generation/add.
2. Rework creator attachment persistence to file-backed metadata and persist retry/repair state.
3. Add duplicate prevention for accepted generated cards.
4. Fix APKG happy-path import and add real round-trip tests.
5. Remove fallback AI Insights retention and reconcile stale completion docs.
6. Run the physical-device plan on the current IPA, especially AI creator, attachments, sync, backup, and clear-session behavior.

REPAIR REQUIRED