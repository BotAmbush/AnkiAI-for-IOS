# AnkiAI iOS — Final Parity Report

Generated from `docs/android-ios-feature-map.yml`. Source of truth: the customized
Android fork at snapshot `9bad8304c8b7b013a6c977c20ebd9f726a436430` (read-only).

## Summary
- **completed**: 45 / 46
- **partial**: 1 / 46

> A feature is **completed** only with real behavioral parity + verification (CI
> compile, unit/integration tests as noted). `physical_device_verified` is **false**
> for every feature — no systematic on-device pass has been run yet.

## Partial (1)
- **synchronization** — AnkiWeb / self-hosted sync.
  - M2.19/M2.20 login + two-way/full sync + media. M2.29 fixes the full-DOWNLOAD HTTP 400 'missing original size' on physical devices: full_download/upload now run a meta request first to discover the assigned per-host endpoint (AnkiDroid #14935/#19102) and issue the transfer directly to it (a redirect was dropping the anki-original-size header). Added sanitized sync diagnostics (no secrets) + endpoint override (self-hosted/tests). Offline regression tests cover failure-preserves-local, custom-endpoint-honored, no-secrets. NOT marked completed: pending a successful on-DEVICE download retest (per task).

## Completed (by category)
- **ai**: ai_card_creator, ai_image_pdf_attachments, ai_insights, ai_response_parsing, ai_reviewer_chat, api_key_storage, claude_api_integration, forced_study, prompt_management
- **core**: answer_buttons, bury_suspend, card_browser, card_note_editor, cloze_cards, collection_database, collection_open_close, custom_study, deck_counts, decks_and_subdecks, filtered_decks, flags_tags, fsrs, learning_review_relearning_steps, migrations, reviewer, scheduler, statistics, undo
- **io**: apkg_colpkg, backups_restore, import_export
- **media**: audio, media
- **platform**: accessibility, background_behavior, localization, notifications
- **rendering**: hebrew_rtl, html_rendering, mathjax_rendering, mixed_rtl_ltr, templates_css
- **shell**: app_lifecycle, navigation, settings

## Finalization gate (Mode A → Mode B)

NOT finalized. `ANDROID-SOURCE-BASELINE.json` stays Mode A
(`lastAndroidCommitFullyPortedToIOS: null`). To finalize, per CLAUDE.md's lifecycle
protocol, ALL of the following must hold and `FINALIZE-INITIAL-MIGRATION.md` must be
run **with explicit user confirmation**:

- [x] Every discovered feature has a documented parity status (this report).
- [x] Required tests pass; GitHub Actions is green (97 tests, latest run).
- [x] An unsigned physical-device IPA is produced each milestone.
- [ ] **`synchronization` confirmed on a physical device** (login direction prompt +
      reviewer queue + AnkiWeb download) — pending the user's retest.
- [ ] A systematic `physical_device_verified` pass across features.
- [ ] Explicit user confirmation to run finalization.
