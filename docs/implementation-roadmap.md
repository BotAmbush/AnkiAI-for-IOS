# Implementation Roadmap

Vertical slices, each: identify Android behavior → write/adjust tests → implement → update parity
checklist + progress.md → commit → (when CI is live) trigger workflow → inspect real result.

## M1 — Native AI layer + shell + CI  ← current
1. ✅ App lifecycle & navigation shell (TabView, environment)
2. ✅ Domain models + `CollectionGateway` + stub
3. ✅ AI provider (Claude client, prompts, parsing, pricing, errors)
4. ✅ AI persistence (`ai_insights.db`) + Keychain
5. ✅ Reviewer chat + creator view models
6. ✅ SwiftUI: decks, reviewer (MathJax), chat, creator, insights, settings
7. ✅ Tests (parser, html, pricing, tips, db, client, chat VM)
8. ✅ GitHub Actions (build → test → unsigned IPA → artifacts)
9. ☐ **Drive CI to green** (build-repair loop) — needs the user to run the workflow
10. ☐ Bundle MathJax; ☐ localized Hebrew/RTL strings; ☐ creator attachments (PhotosPicker + PDFKit)

## M2 — Rust anki backend (core parity)
11. ☐ Build `AnkiCore.xcframework` (rslib for device+sim) in CI
12. ☐ Swift `libanki`: Collection, Decks, Notes, Cards, Notetypes
13. ☐ `BackendCollectionGateway` replaces the stub
14. ☐ Card template/CSS rendering (`render_card`) + media serving to WebView
15. ☐ Real deck list/counts; card browser; note/card editor
16. ☐ Review queue + answer buttons; undo/bury/suspend/flags/tags
17. ☐ Scheduler + FSRS (delegated) + day-rollover tests
18. ☐ Filtered decks / custom study; statistics
19. ☐ Import/export (.apkg/.colpkg); backups & restore
20. ☐ Sync / AnkiWeb (Keychain creds)
21. ☐ `RevlogAnalyzer` + live insights; `ai_card_meta`/`ai_study_log`

## M3 — Platform features & polish
22. ☐ Forced study (iOS-constrained design); scheduler hint overlay
23. ☐ Notifications/reminders; background tasks; sharing/file-open
24. ☐ Accessibility, dark-mode audit, full localization, UI polish

## Definition of done (CLAUDE.md)
Android source unchanged · every feature has a parity status · native Swift/SwiftUI · macOS CI
green · tests pass · unsigned device IPA uploaded with a valid executable · honest known-issues ·
iLoader install docs · no secrets in history · final report splits complete/partial/unsupported.
