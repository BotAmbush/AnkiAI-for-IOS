**Scope**
Audited iOS commit `0fdfbf7c929c3eb2b7f6009d0ea1a45f00cb62f8` against Android commit `522838f52166a7a8e6a3143c5770fb5746aa1dab` in the disposable folders only. I did not modify files, build, commit, push, or query live GitHub.

iOS working tree had one pre-existing modified file: `CLAUDE-REPAIR-REPORT.md`.

**Findings**
**P1 - AI creator can still silently fall back to the first deck when no creator deck is selected**

Evidence: the AI creator UI includes `CreatorDeckBar` and `DeckPickerSheet` at [ChatView.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/Features/Chat/ChatView.swift:38) and [ChatView.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/Features/Chat/ChatView.swift:132), and selected deck id/path are persisted at [AIChatViewModel.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/AI/Chat/AIChatViewModel.swift:118). But generation still does `allDecks.first?.name ?? "Default"` when no selected deck exists at [AIChatViewModel.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/AI/Chat/AIChatViewModel.swift:356). Parsed proposals then resolve to that deck and insertion uses `selectedDeckId ?? proposal.deckId` at [AIChatViewModel.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/AI/Chat/AIChatViewModel.swift:458), so the “choose a deck” UI is not enforced. Tests cover selected-deck behavior but not the no-selection path.

Consequence: creator cards can still land in the first backend deck without an explicit user-selected destination.

Recommended correction: require `selectedDeckId` before generation or before add, remove the first-deck prompt fallback, and add a test for no selected deck.

Blocks stable personal-use build: yes, because it preserves a prior P1 deck-safety class.

**P2 - Reviewer add-card proposal can silently default to deck id 1 after deck resolution failure**

Evidence: reviewer AI add-card proposals resolve/create the model deck before user approval using `try?`, then fall back to `1` at [AIChatViewModel.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/AI/Chat/AIChatViewModel.swift:258). Approval inserts into that stored deck id at [AIChatViewModel.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/AI/Chat/AIChatViewModel.swift:308).

Consequence: a backend failure or bad deck name can silently target Default, and a model-suggested deck may be created before the user accepts the proposal.

Recommended correction: do not create/resolve mutably until approval; surface resolution errors; never default to deck id 1.

Blocks stable personal-use build: no, but it is a real reliability issue.

**P2 - Oversized/failed creator attachment persistence is silently ignored while the attachment may still be sent**

Evidence: file limits exist at [CreatorAttachmentStore.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/AI/CreatorAttachmentStore.swift:26), but `setAttachments` saves each file with `try?` and drops failed refs without surfacing an error at [AIChatViewModel.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/AI/Chat/AIChatViewModel.swift:149). It still sets `lastAttachments = payloads` at [AIChatViewModel.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/AI/Chat/AIChatViewModel.swift:156), so an oversized/non-persisted attachment can be used for the current API call but vanish after relaunch.

Consequence: users can think attachments are safely persisted when they are not.

Recommended correction: make attachment persistence throwing/user-visible and only keep/send attachments that were stored successfully.

Blocks stable personal-use build: no.

**P2 - APKG pre-import backup failure is ignored**

Evidence: `importApkg` attempts a pre-import `.colpkg` backup with `try?` at [BackendCollectionGateway.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/Backend/BackendCollectionGateway.swift:113), then proceeds to import at line 114.

Consequence: if backup export fails, APKG import still runs. Malformed-import preservation is tested, but this weakens the stated “backup first” safety guarantee.

Recommended correction: require backup success before import, or explicitly mark backup as best-effort and rely only on backend transaction safety.

Blocks stable personal-use build: no.

**P3 - Documentation/comment staleness remains**

Evidence: [CreatorSessionStore.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/AI/CreatorSessionStore.swift:3) still says attachments are stored as base64 payloads, while the code stores metadata refs at lines 18-19. `docs/known-issues.md` still contains obsolete APKG “blocked” sections and M1-era “stubbed” statements despite the top repair section saying resolved.

Consequence: reviewers can be misled even though the implementation is mostly better than the stale text.

Recommended correction: remove stale historical contradiction or clearly move it to an archive section.

Blocks stable personal-use build: no.

**Verified Repairs**
AI creator deck picker: present and uses real `creatorDecks()` from backend. Selected id/path persist. Same-leaf-name decks are distinguishable in the picker UI by leaf plus parent path. Missing selected decks are checked before insertion. However, no-selection fallback remains a P1.

Attachment persistence: production now uses scoped files under Application Support via [CreatorAttachmentStore.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/AI/CreatorAttachmentStore.swift:29); session JSON stores metadata only. Size, checksum, and path checks exist. Clear session deletes scoped attachment files and does not touch accepted cards.

Duplicate prevention: creator fingerprints persist and are recorded only after successful `addNote` at [AIChatViewModel.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/AI/Chat/AIChatViewModel.swift:479). Regenerate/relaunch duplicate tests exist.

APKG import: real round-trip tests exist at [BackendApkgRoundTripTests.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAITests/BackendApkgRoundTripTests.swift:15). Backend open sets desktop media paths at [lib.rs](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/rust/anki-backend-ios/src/lib.rs:156). No skips found.

AI Insights: no fabricated `0.85`; retention is `nil` without review data at [InsightsView.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/Features/Insights/InsightsView.swift:68), and tips require non-nil retention at [AITipEngine.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/AI/Insights/AITipEngine.swift:78). Average ease and per-deck retention remain honestly partial.

Sync safety: seeded/unknown upload blocking is present at [KeychainStore.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/Security/KeychainStore.swift:161) and UI blocks upload at [AISettingsView.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/Features/Settings/AISettingsView.swift:105). Full upload requires explicit destructive UI and backup. Full download uses backend temp/integrity/atomic design per [lib.rs](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/rust/anki-backend-ios/src/lib.rs:1518). Background sync persists errors at [BackgroundSync.swift](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/AnkiAI/Platform/BackgroundSync.swift:45).

**Test / CI Evidence**
Local XCTest count: 217 `func test...` methods across 55 XCTestCase classes. No `XCTSkip`/disabled test markers found.

CI workflow builds the backend, builds unsigned physical-device app, runs Simulator tests, packages IPA, uploads artifacts, and verifies compiled file-sharing plist keys at [.github/workflows/ios.yml](C:/Codex-Third-Audit-20260627-211642/AnkiAI-for-IOS/.github/workflows/ios.yml:115).

I did not query live GitHub Actions. Claude’s stated run IDs are documentation evidence only.

**IPA Inspection**
Local `AnkiAI-unsigned.ipa` exists, size `7,477,195` bytes. It is a valid ZIP with `Payload/AnkiAI.app/AnkiAI`. Executable has Mach-O magic `cf fa ed fe`, CPU bytes `0c 00 00 01` (arm64), size `22,265,096` bytes. No `_CodeSignature`, no `embedded.mobileprovision`, no XCTest/test payload found. MathJax `tex-mml-svg.js` is bundled. Info.plist includes `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`, background modes, BG task identifier, iOS 16 minimum. Binary contains real `anki_backend_` symbols and repair-related strings; no obvious embedded `sk-ant-`, Anthropic env key, private key, or password string found.

**Safety Verdicts**
Confirmed P0 still present: no.

Confirmed P1 still present: yes, creator no-selection deck fallback.

Reasonably safe with a real collection when an external backup exists: cautiously yes for core review/sync, but not as a stable accepted build because of the P1 AI creator deck path.

Normal two-way sync reasonably safe: yes, based on code and documented device evidence, not independently live-tested.

Full download reasonably safe: yes by design, with the same caveat.

Unsafe full upload blocked: yes for seeded/unknown provenance.

APKG import sufficiently validated: mostly yes in CI, with the P2 pre-import backup caveat and no device validation.

Can AI retry/regeneration create duplicates: creator path is now guarded; reviewer add-card still lacks a comparable ledger.

Can creator attachment persistence expose or orphan private data: no inline JSON exposure found, but failed/oversize persistence can silently drop attachments.

Can creator deck selection silently choose the wrong deck: yes when no deck is selected, because `allDecks.first` remains reachable.

Is another Claude repair pass required: yes.

**Percentages**
Core Anki functionality: 84%  
Synchronization safety: 82%  
Import/export: 76%  
Backup/restore: 78%  
AI functionality: 78%  
Automated-test confidence: 78%  
Latest repair quality: 80%  
Physical-device validation: 55%  
Overall migration completeness: 79%

Smallest remaining work list:

1. Require an explicit AI creator deck before generation/add; remove `allDecks.first` fallback and test no-selection.
2. Fix reviewer add-card deck resolution so it does not mutate or default before approval.
3. Surface attachment persistence/size-limit failures.
4. Make APKG pre-import backup mandatory or document it as best-effort.
5. Reconcile stale docs/comments.
6. Run the current IPA through the unperformed physical-device AI/APKG/backup retests.

REPAIR REQUIRED