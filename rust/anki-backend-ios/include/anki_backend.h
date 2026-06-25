#ifndef ANKI_BACKEND_H
#define ANKI_BACKEND_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handle to an open collection. */
typedef struct Handle AnkiHandle;

/* Last error for the calling thread, or NULL. Valid until the next call. Do not free. */
const char *anki_backend_last_error(void);

/* Free a string returned by this library. */
void anki_backend_string_free(char *s);

/* Open a collection at `path`. Writes the handle to *out. Returns 0 on success. */
int32_t anki_backend_open(const char *path, AnkiHandle **out);

/* Close a collection (consumes the handle). Safe with NULL. Returns 0 on success. */
int32_t anki_backend_close(AnkiHandle *handle);

/* Deck tree as a JSON array of {deck_id,name,level,new,learn,review}.
   Writes a heap string to *out_json (free with anki_backend_string_free). */
int32_t anki_backend_deck_tree_json(AnkiHandle *handle, char **out_json);

/* Card ids in a deck (and subdecks) as a JSON array of integers. */
int32_t anki_backend_deck_card_ids(AnkiHandle *handle, const char *deck_name, char **out_json);

/* Card ids matching an arbitrary Anki search string (empty = all). */
int32_t anki_backend_search_card_ids(AnkiHandle *handle, const char *search, char **out_json);

/* Render a card: JSON {question_html, answer_html, css}. */
int32_t anki_backend_render_card(AnkiHandle *handle, int64_t card_id, char **out_json);

/* Card info: JSON {note_id,due_date,due_position,interval,ease,reviews,lapses,card_type,deck}. */
int32_t anki_backend_card_info(AnkiHandle *handle, int64_t card_id, char **out_json);

/* Raw note fields: JSON {notetype_id, fields:[...], tags:[...]}. */
int32_t anki_backend_note_fields(AnkiHandle *handle, int64_t note_id, char **out_json);

/* Replace a note's fields (fields_json = JSON array of strings); save (undoable). */
int32_t anki_backend_update_note(AnkiHandle *handle, int64_t note_id, const char *fields_json);

/* Answer/grade a card now via the scheduler. rating: 1=Again 2=Hard 3=Good 4=Easy. */
int32_t anki_backend_answer_card(AnkiHandle *handle, int64_t card_id, int32_t rating);

/* Answer-button interval labels: JSON [again, hard, good, easy]. */
int32_t anki_backend_answer_button_labels(AnkiHandle *handle, int64_t card_id, char **out_json);

/* Suspend a card (excluded from review until unsuspended). */
int32_t anki_backend_suspend_card(AnkiHandle *handle, int64_t card_id);

/* Bury a card (hidden until next day / unburied). */
int32_t anki_backend_bury_card(AnkiHandle *handle, int64_t card_id);

/* Undo the last undoable operation. Non-zero if nothing to undo. */
int32_t anki_backend_undo(AnkiHandle *handle);

/* Move a card to another deck. */
int32_t anki_backend_set_card_deck(AnkiHandle *handle, int64_t card_id, int64_t deck_id);

/* Rename a deck to a new full human name. */
int32_t anki_backend_rename_deck(AnkiHandle *handle, int64_t deck_id, const char *new_name);

/* Delete a deck and its child decks (and their cards). */
int32_t anki_backend_remove_deck(AnkiHandle *handle, int64_t deck_id);

/* Set a card's flag (0=none, 1=red, 2=orange, 3=green, 4=blue). */
int32_t anki_backend_set_card_flag(AnkiHandle *handle, int64_t card_id, uint32_t flag);

/* Add space-separated tags to a note. */
int32_t anki_backend_add_tags_to_note(AnkiHandle *handle, int64_t note_id, const char *tags);

/* Export the whole collection to an .apkg at out_path. */
int32_t anki_backend_export_apkg(AnkiHandle *handle, const char *out_path);

/* Import an .apkg from in_path into the open collection. */
int32_t anki_backend_import_apkg(AnkiHandle *handle, const char *in_path);

/* Write the "Basic" notetype id to *out_id. */
int32_t anki_backend_basic_notetype_id(AnkiHandle *handle, int64_t *out_id);

/* Write the id of the notetype named `name` to *out_id (e.g. "Basic", "Cloze"). */
int32_t anki_backend_notetype_id_by_name(AnkiHandle *handle, const char *name, int64_t *out_id);

/* Resolve/create a deck by full human name; write its id to *out_id. */
int32_t anki_backend_resolve_or_create_deck(AnkiHandle *handle, const char *name, int64_t *out_id);

/* Add a note (fields_json = JSON array of strings); write new note id to *out_note_id. */
int32_t anki_backend_add_note(AnkiHandle *handle, int64_t notetype_id, int64_t deck_id, const char *fields_json, int64_t *out_note_id);

/* AnkiWeb: log in; write the session host key (hkey) to *out_hkey. */
int32_t anki_backend_sync_login(const char *username, const char *password, char **out_hkey);

/* AnkiWeb: full-download the collection for hkey, REPLACING the local col_path. */
int32_t anki_backend_sync_download(const char *col_path, const char *hkey);

/* AnkiWeb: two-way normal sync. *out_required: 0 = synced, 2 = full sync needed. */
int32_t anki_backend_sync(const char *col_path, const char *hkey, int32_t *out_required);

/* AnkiWeb: full-upload local collection, REPLACING the remote. */
int32_t anki_backend_sync_upload(const char *col_path, const char *hkey);

/* AnkiWeb: sync media files (images/audio) for hkey. */
int32_t anki_backend_sync_media(const char *col_path, const char *hkey);

/* Back up the whole collection (with media) to a .colpkg at out_path. */
int32_t anki_backend_export_colpkg(const char *col_path, const char *out_path);

/* Test support: build a deterministic fixture collection at `path`. */
int32_t anki_backend_create_fixture(const char *path);

#ifdef __cplusplus
}
#endif

#endif /* ANKI_BACKEND_H */
