# AnkiAI iOS — Final Parity Report

**FINALIZED 2026-06-25 (Mode A → Mode B).** The iOS app is a complete functional
copy of the customized Android fork at snapshot `9bad8304c8b7b013a6c977c20ebd9f726a436430`,
with documented platform exceptions. Generated from `docs/android-ios-feature-map.yml`.

## Summary
- **completed**: 46 / 46

## Completed (by category)
- **ai**: ai_card_creator, ai_image_pdf_attachments, ai_insights, ai_response_parsing, ai_reviewer_chat, api_key_storage, claude_api_integration, forced_study, prompt_management
- **core**: answer_buttons, bury_suspend, card_browser, card_note_editor, cloze_cards, collection_database, collection_open_close, custom_study, deck_counts, decks_and_subdecks, filtered_decks, flags_tags, fsrs, learning_review_relearning_steps, migrations, reviewer, scheduler, statistics, undo
- **io**: apkg_colpkg, backups_restore, import_export
- **media**: audio, media
- **platform**: accessibility, background_behavior, localization, notifications
- **rendering**: hebrew_rtl, html_rendering, mathjax_rendering, mixed_rtl_ltr, templates_css
- **shell**: app_lifecycle, navigation, settings
- **sync**: synchronization

## Documented platform exceptions
- **forced_study** — iOS can't overlay other apps; in-app required-review session + local notification instead.
- **Deck-options write** — read-only by design (writing deck config on a live synced collection is risky).
- **.apkg file import** — anki deck-merge edge; `.colpkg` restore + AnkiWeb sync are the working import paths.

## Verification
- 122 automated tests pass; GitHub Actions `mode=full` green (run 28156073715); unsigned arm64 IPA produced.
- Device-verified by the user: AnkiWeb download + media; reviewer/browser/AI/editor exercised on device.
- See `docs/android-update-history.md` Entry 2 for the full finalization evidence.
