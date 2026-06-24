# Android Inventory

Read-only inspection of `C:\Users\Evyatar\AndroidStudioProjects\Anki-Android-AI` @ `9bad8304`.

## Gradle modules (`settings.gradle.kts`)
`:AnkiDroid` (app, 681 Kotlin files) · `:libanki` (49 files, thin Rust-backend wrapper) ·
`:api` · `:common`, `:common:android` · `:anki-common` · `:compat` · `:lint-rules` · `:baselineprofile`.

## Core engine (critical finding)
The scheduler, FSRS, sync, DB format, import/export are **not Kotlin** — they are the
upstream Rust `anki` backend via `anki-android-backend` (rsdroid `0.1.64-anki25.09.2`,
`io.github.david-allison:anki-android-backend`). `libanki` wraps it over protobuf.
→ See decision-log DL-001 and scheduler-and-fsrs-analysis.md.

## Build facts
- `compileSdk 36`, `minSdk 24`, `targetSdk 35`, JDK 17, Kotlin + KSP (Room for the AI db).
- Fork adds Room (`2.8.4`) + KSP (`2.3.9`) for `ai_insights.db` only.

## AI fork surface (`com.ichi2.anki.ai`)
`api/` (ClaudeApiClient, LlmApiClient) · `chat/` (ViewModel, Message, Dao, adapter, bottom-sheet, creator static prompt) ·
`data/` (AiDatabase, AiCardMeta(+Dao), AiStudyLog(+Dao)) · `insights/` (TipEngine, dashboards, view models) ·
`analytics/` (RevlogAnalyzer — read-only) · `settings/` (AiSettingsFragment) ·
`enforcement/` (ForcedStudy service/alarm/boot/settings, AiChatLauncherActivity) ·
`hints/` (SchedulerHintOverlay) · `update/` (UpstreamUpdateChecker, UpstreamCheckWorker).

Resources: `layout/fragment_ai_chat.xml`, `item_chat_*`, `item_ai_card_proposal`,
`activity_ai_insights_dashboard`, `overlay_forced_study*`, `values/ai_strings.xml`,
`values-iw/ai_strings.xml` (Hebrew), `xml/preferences_forced_study.xml`, AI drawables.

Integration points (modified upstream files): `DeckPicker.kt` (creator FAB + insights),
`ui/windows/reviewer/ReviewerFragment.kt` (Ask Claude / overlay buttons),
`preferences/Preferences.kt` + `AboutFragment.kt` (AI settings, upstream-update button).

## Detailed mapping
Per-file Android→iOS mapping and status live in `ai-feature-analysis.md` and `feature-parity-checklist.md`.
