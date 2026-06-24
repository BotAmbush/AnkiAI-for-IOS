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

/* Render a card: JSON {question_html, answer_html, css}. */
int32_t anki_backend_render_card(AnkiHandle *handle, int64_t card_id, char **out_json);

/* Answer/grade a card now via the scheduler. rating: 1=Again 2=Hard 3=Good 4=Easy. */
int32_t anki_backend_answer_card(AnkiHandle *handle, int64_t card_id, int32_t rating);

/* Suspend a card (excluded from review until unsuspended). */
int32_t anki_backend_suspend_card(AnkiHandle *handle, int64_t card_id);

/* Bury a card (hidden until next day / unburied). */
int32_t anki_backend_bury_card(AnkiHandle *handle, int64_t card_id);

/* Undo the last undoable operation. Non-zero if nothing to undo. */
int32_t anki_backend_undo(AnkiHandle *handle);

/* Write the "Basic" notetype id to *out_id. */
int32_t anki_backend_basic_notetype_id(AnkiHandle *handle, int64_t *out_id);

/* Resolve/create a deck by full human name; write its id to *out_id. */
int32_t anki_backend_resolve_or_create_deck(AnkiHandle *handle, const char *name, int64_t *out_id);

/* Add a note (fields_json = JSON array of strings); write new note id to *out_note_id. */
int32_t anki_backend_add_note(AnkiHandle *handle, int64_t notetype_id, int64_t deck_id, const char *fields_json, int64_t *out_note_id);

/* Test support: build a deterministic fixture collection at `path`. */
int32_t anki_backend_create_fixture(const char *path);

#ifdef __cplusplus
}
#endif

#endif /* ANKI_BACKEND_H */
