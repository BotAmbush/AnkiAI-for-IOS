//! Narrow C-ABI bridge over the pinned upstream Anki Rust backend.
//!
//! Only the M2.1 *read path* is exposed for production use:
//!   - open a collection
//!   - read the deck tree (names + new/learn/review counts) as JSON
//!   - close cleanly
//!
//! A test-support `create_fixture` function builds a deterministic collection
//! and is used only by integration tests (never by the production app).
//!
//! Ownership/error model:
//!   - `anki_backend_open` returns an opaque `*mut Handle`; the caller owns it
//!     and must pass it to exactly one `anki_backend_close`.
//!   - JSON strings returned via out-params are heap-allocated; the caller must
//!     free them with `anki_backend_string_free`.
//!   - On error, functions return a non-zero code and set a thread-local message
//!     retrievable via `anki_backend_last_error` (valid until the next call).
//!   - No raw Rust types cross the boundary — only C strings, ints, and the
//!     opaque handle pointer.

use std::cell::RefCell;
use std::ffi::{c_char, c_int, CStr, CString};
use std::path::PathBuf;
use std::ptr;

use anki::collection::{Collection, CollectionBuilder};
use anki::prelude::*;
use anki::import_export::package::import_colpkg;
use anki::import_export::ImportProgress;
use anki::search::SortMode;
use anki::services::DecksService;
use anki::services::NotesService;
use anki_proto::decks::deck::filtered::SearchTerm as FilteredSearchTerm;
use anki_proto::decks::DeckId as PbDeckId;
use anki_proto::decks::DeckTreeNode;
use anki_proto::decks::RenameDeckRequest;
use anki_proto::import_export::{ExportAnkiPackageOptions, ImportAnkiPackageOptions};
use anki_proto::notes::{NoteId as PbNoteId, UpdateNotesRequest};
use anki::sync::collection::normal::SyncActionRequired;
use anki::sync::collection::status::online_sync_status_check;
use anki::sync::http_client::HttpSyncClient;
use anki::sync::login::{sync_login, SyncAuth};
use anki::sync::media::progress::MediaSyncProgress;
use anki_proto::scheduler::bury_or_suspend_cards_request::Mode as BuryOrSuspendMode;

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
    /// Sanitized, human-readable diagnostics for the last sync operation. NEVER
    /// contains passwords, session keys, auth headers, or collection contents.
    static SYNC_LOG: RefCell<Vec<String>> = const { RefCell::new(Vec::new() ) };
}

fn set_last_error(msg: String) {
    LAST_ERROR.with(|e| *e.borrow_mut() = CString::new(msg).ok());
}

fn sync_log_reset() {
    SYNC_LOG.with(|l| l.borrow_mut().clear());
}

fn sync_log(msg: impl Into<String>) {
    SYNC_LOG.with(|l| l.borrow_mut().push(msg.into()));
}

/// Host (no scheme/path/query) of a URL string, for safe logging. Returns
/// "default" for None and "<unparseable>" if it can't be parsed.
fn endpoint_host(ep: Option<&str>) -> String {
    match ep {
        None => "default".to_string(),
        Some(s) => match reqwest::Url::parse(s) {
            Ok(u) => u.host_str().unwrap_or("<no-host>").to_string(),
            Err(_) => "<unparseable>".to_string(),
        },
    }
}

/// A coarse, non-sensitive error category (the leading variant/type name only —
/// never the message body, which for sync errors may echo server text).
fn error_category<E: std::fmt::Debug>(e: &E) -> String {
    let dbg = format!("{e:?}");
    let cat: String = dbg
        .chars()
        .take_while(|c| c.is_alphanumeric() || *c == '_')
        .collect();
    if cat.is_empty() {
        "Unknown".to_string()
    } else {
        cat
    }
}

/// Take (and clear) the sanitized sync diagnostics log. Caller frees the string.
#[no_mangle]
pub extern "C" fn anki_backend_take_sync_log() -> *mut c_char {
    let joined = SYNC_LOG.with(|l| {
        let v = l.borrow();
        v.join("\n")
    });
    sync_log_reset();
    match CString::new(joined) {
        Ok(c) => c.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Opaque handle wrapping an open collection.
pub struct Handle {
    col: Collection,
}

unsafe fn cstr_to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    Some(CStr::from_ptr(ptr).to_string_lossy().into_owned())
}

/// Returns the last error message for this thread, or NULL. Valid until the next
/// bridge call on the same thread. Do not free.
#[no_mangle]
pub extern "C" fn anki_backend_last_error() -> *const c_char {
    LAST_ERROR.with(|e| match &*e.borrow() {
        Some(s) => s.as_ptr(),
        None => ptr::null(),
    })
}

/// Free a string previously returned by this library.
#[no_mangle]
pub extern "C" fn anki_backend_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

/// Open a collection at `path`. On success writes the handle to `out` and
/// returns 0. On failure returns non-zero and sets the last error.
#[no_mangle]
pub extern "C" fn anki_backend_open(path: *const c_char, out: *mut *mut Handle) -> c_int {
    let path = match unsafe { cstr_to_string(path) } {
        Some(p) => p,
        None => {
            set_last_error("null path".into());
            return 1;
        }
    };
    if out.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    match CollectionBuilder::new(PathBuf::from(path)).build() {
        Ok(col) => {
            let handle = Box::new(Handle { col });
            unsafe { *out = Box::into_raw(handle) };
            0
        }
        Err(e) => {
            set_last_error(format!("open failed: {e}"));
            2
        }
    }
}

/// Close a collection opened with `anki_backend_open`. Safe to call with NULL.
/// Returns 0 on a clean close. Consumes the handle.
#[no_mangle]
pub extern "C" fn anki_backend_close(handle: *mut Handle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    let handle = unsafe { Box::from_raw(handle) };
    // None = keep the current schema version (no downgrade / destructive write).
    match handle.col.close(None) {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(format!("close failed: {e}"));
            2
        }
    }
}

/// Build the deck tree (with today's new/learn/review counts) and return it as a
/// JSON array of `{deck_id,name,level,new,learn,review}` via `out_json`.
/// Caller frees the string with `anki_backend_string_free`.
#[no_mangle]
pub extern "C" fn anki_backend_deck_tree_json(
    handle: *mut Handle,
    out_json: *mut *mut c_char,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    if out_json.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    let now = TimestampSecs::now();
    match handle.col.deck_tree(Some(now)) {
        Ok(tree) => {
            let mut decks: Vec<serde_json::Value> = Vec::new();
            flatten_tree(&tree, "", &mut decks);
            let json = serde_json::to_string(&decks).unwrap_or_else(|_| "[]".into());
            match CString::new(json) {
                Ok(c) => {
                    unsafe { *out_json = c.into_raw() };
                    0
                }
                Err(_) => {
                    set_last_error("deck json contained NUL".into());
                    3
                }
            }
        }
        Err(e) => {
            set_last_error(format!("deck_tree failed: {e}"));
            2
        }
    }
}

/// Walk the deck tree, building full "Parent::Child" names and emitting one JSON
/// object per real deck (the synthetic root, deck_id 0, is skipped).
fn flatten_tree(node: &DeckTreeNode, parent_full: &str, out: &mut Vec<serde_json::Value>) {
    let full = if node.name.is_empty() {
        String::new()
    } else if parent_full.is_empty() {
        node.name.clone()
    } else {
        format!("{parent_full}::{}", node.name)
    };

    if node.deck_id != 0 {
        out.push(serde_json::json!({
            "deck_id": node.deck_id,
            "name": full,
            "level": node.level,
            "new": node.new_count,
            "learn": node.learn_count,
            "review": node.review_count,
        }));
    }
    for child in &node.children {
        flatten_tree(child, &full, out);
    }
}

/// Return the card ids in a deck (and its subdecks) as a JSON array of integers,
/// via `out_json`. Caller frees the string with `anki_backend_string_free`.
#[no_mangle]
pub extern "C" fn anki_backend_deck_card_ids(
    handle: *mut Handle,
    deck_name: *const c_char,
    out_json: *mut *mut c_char,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    let name = match unsafe { cstr_to_string(deck_name) } {
        Some(n) => n,
        None => {
            set_last_error("null deck name".into());
            return 1;
        }
    };
    if out_json.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    let escaped = name.replace('\\', "\\\\").replace('"', "\\\"");
    let search = format!("deck:\"{escaped}\"");
    match handle.col.search_cards(search.as_str(), SortMode::NoOrder) {
        Ok(cids) => {
            let ids: Vec<i64> = cids.iter().map(|c| c.0).collect();
            let json = serde_json::to_string(&ids).unwrap_or_else(|_| "[]".into());
            match CString::new(json) {
                Ok(c) => {
                    unsafe { *out_json = c.into_raw() };
                    0
                }
                Err(_) => {
                    set_last_error("card ids json contained NUL".into());
                    3
                }
            }
        }
        Err(e) => {
            set_last_error(format!("search_cards failed: {e}"));
            2
        }
    }
}

/// Card ids matching an arbitrary Anki search string (e.g. "deck:Math", "tag:x",
/// free text), as a JSON array of integers via `out_json`. Empty search = all.
#[no_mangle]
pub extern "C" fn anki_backend_search_card_ids(
    handle: *mut Handle,
    search: *const c_char,
    out_json: *mut *mut c_char,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    let search = match unsafe { cstr_to_string(search) } {
        Some(s) => s,
        None => {
            set_last_error("null search".into());
            return 1;
        }
    };
    if out_json.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    match handle.col.search_cards(search.as_str(), SortMode::NoOrder) {
        Ok(cids) => {
            let ids: Vec<i64> = cids.iter().map(|c| c.0).collect();
            let json = serde_json::to_string(&ids).unwrap_or_else(|_| "[]".into());
            match CString::new(json) {
                Ok(c) => {
                    unsafe { *out_json = c.into_raw() };
                    0
                }
                Err(_) => {
                    set_last_error("search json contained NUL".into());
                    3
                }
            }
        }
        Err(e) => {
            set_last_error(format!("search_cards failed: {e}"));
            2
        }
    }
}

/// Card info (scheduling stats) as JSON via `out_json`:
/// `{due_date, due_position, interval, ease, reviews, lapses, card_type, deck}`.
/// `due_date` is epoch seconds (review/learning) or null; `due_position` is the
/// new-queue position or null.
#[no_mangle]
pub extern "C" fn anki_backend_card_info(
    handle: *mut Handle,
    card_id: i64,
    out_json: *mut *mut c_char,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    if out_json.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    match handle.col.card_stats(CardId(card_id)) {
        Ok(s) => {
            let json = serde_json::json!({
                "note_id": s.note_id,
                "due_date": s.due_date,
                "due_position": s.due_position,
                "interval": s.interval,
                "ease": s.ease,
                "reviews": s.reviews,
                "lapses": s.lapses,
                "card_type": s.card_type,
                "deck": s.deck,
            })
            .to_string();
            match CString::new(json) {
                Ok(c) => {
                    unsafe { *out_json = c.into_raw() };
                    0
                }
                Err(_) => {
                    set_last_error("card info json contained NUL".into());
                    3
                }
            }
        }
        Err(e) => {
            set_last_error(format!("card_stats failed: {e}"));
            2
        }
    }
}

/// Render an existing card via the backend (templates + CSS). Returns JSON
/// `{question_html, answer_html, css}` via `out_json`. Caller frees the string.
#[no_mangle]
pub extern "C" fn anki_backend_render_card(
    handle: *mut Handle,
    card_id: i64,
    out_json: *mut *mut c_char,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    if out_json.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    match handle.col.render_existing_card(CardId(card_id), false, false) {
        Ok(out) => {
            let question = out.question().into_owned();
            let answer = out.answer().into_owned();
            let css = out.css;
            let json = serde_json::json!({
                "question_html": question,
                "answer_html": answer,
                "css": css,
            })
            .to_string();
            match CString::new(json) {
                Ok(c) => {
                    unsafe { *out_json = c.into_raw() };
                    0
                }
                Err(_) => {
                    set_last_error("render json contained NUL".into());
                    3
                }
            }
        }
        Err(e) => {
            set_last_error(format!("render_existing_card failed: {e}"));
            2
        }
    }
}

/// Return the four answer-button interval labels for a card as a JSON array of
/// strings in [again, hard, good, easy] order (e.g. ["<1m","<10m","1d","4d"]).
#[no_mangle]
pub extern "C" fn anki_backend_answer_button_labels(
    handle: *mut Handle,
    card_id: i64,
    out_json: *mut *mut c_char,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    if out_json.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    let states = match handle.col.get_scheduling_states(CardId(card_id)) {
        Ok(s) => s,
        Err(e) => {
            set_last_error(format!("get_scheduling_states failed: {e}"));
            return 2;
        }
    };
    match handle.col.describe_next_states(&states) {
        Ok(labels) => {
            let json = serde_json::to_string(&labels).unwrap_or_else(|_| "[]".into());
            match CString::new(json) {
                Ok(c) => {
                    unsafe { *out_json = c.into_raw() };
                    0
                }
                Err(_) => {
                    set_last_error("labels json contained NUL".into());
                    3
                }
            }
        }
        Err(e) => {
            set_last_error(format!("describe_next_states failed: {e}"));
            2
        }
    }
}

/// Answer (grade) a card now with `rating` (1=Again 2=Hard 3=Good 4=Easy),
/// driving the real backend scheduler. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_answer_card(
    handle: *mut Handle,
    card_id: i64,
    rating: i32,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    if !(1..=4).contains(&rating) {
        set_last_error(format!("invalid rating {rating} (expected 1..=4)"));
        return 1;
    }
    // External scale is the standard Anki 1=Again 2=Hard 3=Good 4=Easy.
    // grade_now uses a 0-based scale (0=Again 1=Hard 2=Good 3=Easy), so subtract 1.
    match handle.col.grade_now(&[CardId(card_id)], rating - 1) {
        Ok(_) => 0,
        Err(e) => {
            set_last_error(format!("answer_card failed: {e}"));
            2
        }
    }
}

/// Set the deck whose scheduler queue is being studied. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_set_current_deck(handle: *mut Handle, deck_id: i64) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    match handle.col.set_current_deck(DeckId(deck_id)) {
        Ok(_) => 0,
        Err(e) => {
            set_last_error(format!("set_current_deck failed: {e}"));
            2
        }
    }
}

/// Next DUE card from the scheduler queue for the current deck (respecting the
/// queue: due/learning/new order, daily limits; suspended/buried/future excluded).
/// Writes the card id to `out_card_id` (-1 if the queue is empty) and the remaining
/// new/learning/review counts. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_next_card(
    handle: *mut Handle,
    out_card_id: *mut i64,
    out_new: *mut i32,
    out_learn: *mut i32,
    out_review: *mut i32,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    if out_card_id.is_null() || out_new.is_null() || out_learn.is_null() || out_review.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    match handle.col.get_queued_cards(1, false) {
        Ok(q) => {
            unsafe {
                *out_card_id = q.cards.first().map(|c| c.card.id.0).unwrap_or(-1);
                *out_new = q.new_count as i32;
                *out_learn = q.learning_count as i32;
                *out_review = q.review_count as i32;
            }
            0
        }
        Err(e) => {
            set_last_error(format!("get_queued_cards failed: {e}"));
            2
        }
    }
}

/// Suspend a card (excluded from review until unsuspended). Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_suspend_card(handle: *mut Handle, card_id: i64) -> c_int {
    bury_or_suspend(handle, card_id, BuryOrSuspendMode::Suspend, "suspend")
}

/// Bury a card (hidden until the next day / unburied). Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_bury_card(handle: *mut Handle, card_id: i64) -> c_int {
    bury_or_suspend(handle, card_id, BuryOrSuspendMode::BuryUser, "bury")
}

fn bury_or_suspend(
    handle: *mut Handle,
    card_id: i64,
    mode: BuryOrSuspendMode,
    what: &str,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    match handle.col.bury_or_suspend_cards(&[CardId(card_id)], mode) {
        Ok(_) => 0,
        Err(e) => {
            set_last_error(format!("{what} failed: {e}"));
            2
        }
    }
}

/// Set a card's flag (0=none, 1=red, 2=orange, 3=green, 4=blue, …). Returns 0.
#[no_mangle]
pub extern "C" fn anki_backend_set_card_flag(
    handle: *mut Handle,
    card_id: i64,
    flag: u32,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    match handle.col.set_card_flag(&[CardId(card_id)], flag) {
        Ok(_) => 0,
        Err(e) => {
            set_last_error(format!("set_card_flag failed: {e}"));
            2
        }
    }
}

/// Add space-separated `tags` to a note. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_add_tags_to_note(
    handle: *mut Handle,
    note_id: i64,
    tags: *const c_char,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    let tags = match unsafe { cstr_to_string(tags) } {
        Some(t) => t,
        None => {
            set_last_error("null tags".into());
            return 1;
        }
    };
    match handle.col.add_tags_to_notes(&[NoteId(note_id)], &tags) {
        Ok(_) => 0,
        Err(e) => {
            set_last_error(format!("add_tags_to_notes failed: {e}"));
            2
        }
    }
}

/// Rename a deck to a new full human name. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_rename_deck(
    handle: *mut Handle,
    deck_id: i64,
    new_name: *const c_char,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    let new_name = match unsafe { cstr_to_string(new_name) } {
        Some(n) => n,
        None => {
            set_last_error("null name".into());
            return 1;
        }
    };
    match DecksService::rename_deck(
        &mut handle.col,
        RenameDeckRequest { deck_id, new_name },
    ) {
        Ok(_) => 0,
        Err(e) => {
            set_last_error(format!("rename_deck failed: {e}"));
            2
        }
    }
}

/// Delete a deck and its child decks (and their cards). Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_remove_deck(handle: *mut Handle, deck_id: i64) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    match handle.col.remove_decks_and_child_decks(&[DeckId(deck_id)]) {
        Ok(_) => 0,
        Err(e) => {
            set_last_error(format!("remove_decks failed: {e}"));
            2
        }
    }
}

/// Create (or rebuild) a filtered deck named `name` that gathers up to `limit`
/// cards matching the Anki `search`. Writes the deck id to `out_deck_id`.
/// This is the engine behind custom study. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_create_filtered_deck(
    handle: *mut Handle,
    name: *const c_char,
    search: *const c_char,
    limit: u32,
    out_deck_id: *mut i64,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    let name = match unsafe { cstr_to_string(name) } {
        Some(n) => n,
        None => {
            set_last_error("null name".into());
            return 1;
        }
    };
    let search = match unsafe { cstr_to_string(search) } {
        Some(s) => s,
        None => {
            set_last_error("null search".into());
            return 1;
        }
    };
    if out_deck_id.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    // Start from a fresh filtered-deck template (DeckId 0 = create new).
    let mut fd = match DecksService::get_or_create_filtered_deck(&mut handle.col, PbDeckId { did: 0 }) {
        Ok(f) => f,
        Err(e) => {
            set_last_error(format!("get_or_create_filtered_deck failed: {e}"));
            return 2;
        }
    };
    fd.name = name;
    if let Some(cfg) = fd.config.as_mut() {
        if let Some(term) = cfg.search_terms.first_mut() {
            term.search = search;
            term.limit = limit;
        } else {
            cfg.search_terms.push(FilteredSearchTerm {
                search,
                limit,
                order: 0,
            });
        }
    }
    match DecksService::add_or_update_filtered_deck(&mut handle.col, fd) {
        Ok(out) => {
            unsafe { *out_deck_id = out.id };
            0
        }
        Err(e) => {
            set_last_error(format!("add_or_update_filtered_deck failed: {e:?}"));
            2
        }
    }
}

/// Move a card to another deck. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_set_card_deck(
    handle: *mut Handle,
    card_id: i64,
    deck_id: i64,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    match handle.col.set_deck(&[CardId(card_id)], DeckId(deck_id)) {
        Ok(_) => 0,
        Err(e) => {
            set_last_error(format!("set_deck failed: {e}"));
            2
        }
    }
}

/// Undo the last undoable operation. Returns 0 on success, non-zero if there is
/// nothing to undo (message in last_error).
#[no_mangle]
pub extern "C" fn anki_backend_undo(handle: *mut Handle) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    match handle.col.undo() {
        Ok(_) => 0,
        Err(e) => {
            set_last_error(format!("undo failed: {e}"));
            2
        }
    }
}

/// Write the id of the "Basic" notetype to `out_id`. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_basic_notetype_id(handle: *mut Handle, out_id: *mut i64) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    if out_id.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    match handle.col.get_notetype_by_name("Basic") {
        Ok(Some(nt)) => {
            unsafe { *out_id = nt.id.0 };
            0
        }
        Ok(None) => {
            set_last_error("Basic notetype not found".into());
            2
        }
        Err(e) => {
            set_last_error(format!("get_notetype_by_name failed: {e}"));
            2
        }
    }
}

/// Write the id of the notetype named `name` to `out_id` (0 if not found, with
/// an error set). Generalizes basic_notetype_id (e.g. "Basic", "Cloze").
#[no_mangle]
pub extern "C" fn anki_backend_notetype_id_by_name(
    handle: *mut Handle,
    name: *const c_char,
    out_id: *mut i64,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    let name = match unsafe { cstr_to_string(name) } {
        Some(n) => n,
        None => {
            set_last_error("null name".into());
            return 1;
        }
    };
    if out_id.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    match handle.col.get_notetype_by_name(&name) {
        Ok(Some(nt)) => {
            unsafe { *out_id = nt.id.0 };
            0
        }
        Ok(None) => {
            set_last_error(format!("notetype '{name}' not found"));
            2
        }
        Err(e) => {
            set_last_error(format!("get_notetype_by_name failed: {e}"));
            2
        }
    }
}

/// Resolve a deck by full human name, creating it (and parents) if needed.
/// Writes the deck id to `out_id`. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_resolve_or_create_deck(
    handle: *mut Handle,
    name: *const c_char,
    out_id: *mut i64,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    let name = match unsafe { cstr_to_string(name) } {
        Some(n) => n,
        None => {
            set_last_error("null deck name".into());
            return 1;
        }
    };
    if out_id.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    match handle.col.get_or_create_normal_deck(&name) {
        Ok(deck) => {
            unsafe { *out_id = deck.id.0 };
            0
        }
        Err(e) => {
            set_last_error(format!("get_or_create_normal_deck failed: {e}"));
            2
        }
    }
}

/// Add a note of `notetype_id` to deck `deck_id` with `fields_json` (a JSON array
/// of strings). Writes the new note id to `out_note_id`. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_add_note(
    handle: *mut Handle,
    notetype_id: i64,
    deck_id: i64,
    fields_json: *const c_char,
    out_note_id: *mut i64,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    let fields_json = match unsafe { cstr_to_string(fields_json) } {
        Some(f) => f,
        None => {
            set_last_error("null fields".into());
            return 1;
        }
    };
    if out_note_id.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    let fields: Vec<String> = match serde_json::from_str(&fields_json) {
        Ok(f) => f,
        Err(e) => {
            set_last_error(format!("invalid fields json: {e}"));
            return 1;
        }
    };
    match add_note_impl(&mut handle.col, notetype_id, deck_id, &fields) {
        Ok(nid) => {
            unsafe { *out_note_id = nid };
            0
        }
        Err(e) => {
            set_last_error(format!("add_note failed: {e}"));
            2
        }
    }
}

fn add_note_impl(col: &mut Collection, notetype_id: i64, deck_id: i64, fields: &[String]) -> Result<i64> {
    let nt = col
        .get_notetype(NotetypeId(notetype_id))?
        .or_invalid("no such notetype")?;
    let mut note = nt.new_note();
    let count = note.fields().len();
    for (i, value) in fields.iter().enumerate() {
        if i < count {
            note.set_field(i, value.as_str())?;
        }
    }
    col.add_note(&mut note, DeckId(deck_id))?;
    Ok(note.id.0)
}

/// Export the whole collection to an `.apkg` at `out_path`. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_export_apkg(
    handle: *mut Handle,
    out_path: *const c_char,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    let out_path = match unsafe { cstr_to_string(out_path) } {
        Some(p) => p,
        None => {
            set_last_error("null out path".into());
            return 1;
        }
    };
    // Include scheduling + deck configs so decks round-trip with their kinds.
    let opts = ExportAnkiPackageOptions {
        with_scheduling: true,
        with_deck_configs: true,
        with_media: false,
        legacy: false,
    };
    match handle.col.export_apkg(&out_path, opts, "", None) {
        Ok(_) => 0,
        Err(e) => {
            set_last_error(format!("export_apkg failed: {e}"));
            2
        }
    }
}

/// Import an `.apkg` from `in_path` into the open collection. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_import_apkg(
    handle: *mut Handle,
    in_path: *const c_char,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    let in_path = match unsafe { cstr_to_string(in_path) } {
        Some(p) => p,
        None => {
            set_last_error("null in path".into());
            return 1;
        }
    };
    let opts = ImportAnkiPackageOptions {
        with_scheduling: true,
        with_deck_configs: true,
        ..Default::default()
    };
    match handle.col.import_apkg(&in_path, opts) {
        Ok(_) => 0,
        Err(e) => {
            // Debug format so opaque errors (e.g. InvalidInput { info }) surface.
            set_last_error(format!("import_apkg failed: {e:?}"));
            2
        }
    }
}

/// Raw note fields/notetype/tags as JSON `{notetype_id, fields:[...], tags:[...]}`
/// via the NotesService (so editing existing notes works without rendering).
#[no_mangle]
pub extern "C" fn anki_backend_note_fields(
    handle: *mut Handle,
    note_id: i64,
    out_json: *mut *mut c_char,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    if out_json.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    match handle.col.get_note(PbNoteId { nid: note_id }) {
        Ok(note) => {
            let (field_names, notetype_name) = match handle
                .col
                .get_notetype(NotetypeId(note.notetype_id))
            {
                Ok(Some(nt)) => (
                    nt.fields.iter().map(|f| f.name.clone()).collect::<Vec<_>>(),
                    nt.name.clone(),
                ),
                _ => (Vec::new(), String::new()),
            };
            let json = serde_json::json!({
                "notetype_id": note.notetype_id,
                "notetype_name": notetype_name,
                "fields": note.fields,
                "field_names": field_names,
                "tags": note.tags,
            })
            .to_string();
            match CString::new(json) {
                Ok(c) => {
                    unsafe { *out_json = c.into_raw() };
                    0
                }
                Err(_) => {
                    set_last_error("note json contained NUL".into());
                    3
                }
            }
        }
        Err(e) => {
            set_last_error(format!("get_note failed: {e}"));
            2
        }
    }
}

/// Replace a note's fields with `fields_json` (a JSON array of strings) and save
/// it (undoable). Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_update_note(
    handle: *mut Handle,
    note_id: i64,
    fields_json: *const c_char,
) -> c_int {
    let handle = match unsafe { handle.as_mut() } {
        Some(h) => h,
        None => {
            set_last_error("null handle".into());
            return 1;
        }
    };
    let fields_json = match unsafe { cstr_to_string(fields_json) } {
        Some(f) => f,
        None => {
            set_last_error("null fields".into());
            return 1;
        }
    };
    let fields: Vec<String> = match serde_json::from_str(&fields_json) {
        Ok(f) => f,
        Err(e) => {
            set_last_error(format!("invalid fields json: {e}"));
            return 1;
        }
    };
    let mut note = match handle.col.get_note(PbNoteId { nid: note_id }) {
        Ok(n) => n,
        Err(e) => {
            set_last_error(format!("get_note failed: {e}"));
            return 2;
        }
    };
    note.fields = fields;
    match handle.col.update_notes(UpdateNotesRequest {
        notes: vec![note],
        skip_undo_entry: false,
    }) {
        Ok(_) => 0,
        Err(e) => {
            set_last_error(format!("update_notes failed: {e}"));
            2
        }
    }
}

// ─── AnkiWeb sync ──────────────────────────────────────────────────────────────

fn sync_client() -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(120))
        .build()
        .unwrap_or_else(|_| reqwest::Client::new())
}

fn sync_runtime() -> std::io::Result<tokio::runtime::Runtime> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
}

/// Log in to AnkiWeb with `username`/`password`; write the session host key (hkey)
/// to `out_hkey` (free with anki_backend_string_free). Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_sync_login(
    username: *const c_char,
    password: *const c_char,
    out_hkey: *mut *mut c_char,
) -> c_int {
    let username = match unsafe { cstr_to_string(username) } {
        Some(u) => u,
        None => {
            set_last_error("null username".into());
            return 1;
        }
    };
    let password = match unsafe { cstr_to_string(password) } {
        Some(p) => p,
        None => {
            set_last_error("null password".into());
            return 1;
        }
    };
    if out_hkey.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    let rt = match sync_runtime() {
        Ok(r) => r,
        Err(e) => {
            set_last_error(format!("runtime: {e}"));
            return 2;
        }
    };
    match rt.block_on(sync_login(username, password, None, sync_client())) {
        Ok(auth) => match CString::new(auth.hkey) {
            Ok(c) => {
                unsafe { *out_hkey = c.into_raw() };
                0
            }
            Err(_) => {
                set_last_error("hkey contained NUL".into());
                3
            }
        },
        Err(e) => {
            set_last_error(format!("sync_login failed: {e:?}"));
            2
        }
    }
}

/// Full-download the AnkiWeb collection for `hkey`, REPLACING the local collection
/// at `col_path`. Returns 0 on success. (Collection only; media sync is separate.)
///
/// Endpoint discovery (AnkiDroid PR #14935 / #19102): AnkiWeb shards accounts onto
/// per-host sync servers. We MUST run a meta request first to discover the assigned
/// endpoint and issue the download directly to it — otherwise the request reaches
/// the default host, gets redirected, and the redirect drops the
/// `anki-original-size` header → HTTP 400 "missing original size".
///
/// `endpoint_override` (nullable) sets the base endpoint (self-hosted sync servers
/// and deterministic tests); pass NULL for AnkiWeb.
///
/// Safety: `full_download` itself downloads into a temp file, rebuilds it with an
/// integrity check, and only then atomically renames over `col_path`; the original
/// collection is left untouched on any HTTP/decompression/db/validation failure.
#[no_mangle]
pub extern "C" fn anki_backend_sync_download(
    col_path: *const c_char,
    hkey: *const c_char,
    endpoint_override: *const c_char,
) -> c_int {
    sync_log_reset();
    let col_path = match unsafe { cstr_to_string(col_path) } {
        Some(p) => p,
        None => {
            set_last_error("null col path".into());
            return 1;
        }
    };
    let hkey = match unsafe { cstr_to_string(hkey) } {
        Some(h) => h,
        None => {
            set_last_error("null hkey".into());
            return 1;
        }
    };
    let override_ep = unsafe { cstr_to_string(endpoint_override) };
    let base_endpoint: Option<reqwest::Url> = match override_ep.as_deref() {
        Some(s) if !s.is_empty() => match reqwest::Url::parse(s) {
            Ok(u) => Some(u),
            Err(e) => {
                set_last_error(format!("invalid endpoint override: {e}"));
                return 1;
            }
        },
        _ => None,
    };

    sync_log("op=download");
    sync_log(format!(
        "base_endpoint={}",
        endpoint_host(base_endpoint.as_ref().map(|u| u.as_str()))
    ));

    let col = match CollectionBuilder::new(PathBuf::from(&col_path)).build() {
        Ok(c) => c,
        Err(e) => {
            set_last_error(format!("open failed: {e}"));
            sync_log("error=open_failed");
            return 2;
        }
    };
    let rt = match sync_runtime() {
        Ok(r) => r,
        Err(e) => {
            set_last_error(format!("runtime: {e}"));
            return 2;
        }
    };

    let auth = SyncAuth {
        hkey,
        endpoint: base_endpoint.clone(),
        io_timeout_secs: None,
    };

    // 1. Discover the assigned endpoint via a meta request (with redirect).
    let local_meta = match col.sync_meta() {
        Ok(m) => m,
        Err(e) => {
            set_last_error(format!("sync_meta failed: {e:?}"));
            sync_log("error=sync_meta_failed");
            return 2;
        }
    };
    let mut client = HttpSyncClient::new(auth.clone(), sync_client());
    let state = match rt.block_on(online_sync_status_check(local_meta, &mut client)) {
        Ok(s) => s,
        Err(e) => {
            sync_log("meta=err");
            sync_log(format!("error_category={}", error_category(&e)));
            set_last_error(format!("sync status check failed: {e:?}"));
            // Local collection untouched (no download attempted).
            return 2;
        }
    };
    sync_log("meta=ok");
    sync_log(format!(
        "new_endpoint={}",
        endpoint_host(state.new_endpoint.as_deref())
    ));

    // 2. Persist the discovered endpoint into the auth used for the full download.
    let mut download_auth = auth;
    let mut endpoint_updated = false;
    if let Some(ep) = state.new_endpoint.as_deref() {
        match reqwest::Url::parse(ep) {
            Ok(u) => {
                download_auth.endpoint = Some(u);
                endpoint_updated = true;
            }
            Err(e) => {
                set_last_error(format!("server returned an invalid endpoint: {e}"));
                sync_log("error=invalid_new_endpoint");
                return 2;
            }
        }
    }
    sync_log(format!("endpoint_updated={endpoint_updated}"));
    sync_log(format!(
        "download_endpoint={}",
        endpoint_host(download_auth.endpoint.as_ref().map(|u| u.as_str()))
    ));

    // 3. Full download directly to the assigned endpoint (no header-dropping redirect).
    match rt.block_on(col.full_download(download_auth, sync_client())) {
        Ok(()) => {
            sync_log("full_download=ok");
            0
        }
        Err(e) => {
            sync_log("full_download=err");
            sync_log(format!("error_category={}", error_category(&e)));
            set_last_error(format!("sync_download failed: {e:?}"));
            2
        }
    }
}

/// Two-way normal sync of the collection at `col_path` for `hkey`. Writes the
/// outcome to `out_required`: 0 = synced/no-changes, 2 = a full sync is required
/// (the caller must choose download or upload). Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_sync(
    col_path: *const c_char,
    hkey: *const c_char,
    out_required: *mut i32,
) -> c_int {
    let col_path = match unsafe { cstr_to_string(col_path) } {
        Some(p) => p,
        None => {
            set_last_error("null col path".into());
            return 1;
        }
    };
    let hkey = match unsafe { cstr_to_string(hkey) } {
        Some(h) => h,
        None => {
            set_last_error("null hkey".into());
            return 1;
        }
    };
    if out_required.is_null() {
        set_last_error("null out pointer".into());
        return 1;
    }
    let mut col = match CollectionBuilder::new(PathBuf::from(&col_path)).build() {
        Ok(c) => c,
        Err(e) => {
            set_last_error(format!("open failed: {e}"));
            return 2;
        }
    };
    let auth = SyncAuth {
        hkey,
        endpoint: None,
        io_timeout_secs: None,
    };
    let rt = match sync_runtime() {
        Ok(r) => r,
        Err(e) => {
            set_last_error(format!("runtime: {e}"));
            return 2;
        }
    };
    let result = rt.block_on(col.normal_sync(auth, sync_client()));
    let _ = col.close(None);
    match result {
        Ok(out) => {
            let required = match out.required {
                SyncActionRequired::FullSyncRequired { .. } => 2,
                _ => 0,
            };
            unsafe { *out_required = required };
            0
        }
        Err(e) => {
            set_last_error(format!("sync failed: {e:?}"));
            2
        }
    }
}

/// Full-upload the local collection at `col_path` to AnkiWeb for `hkey`,
/// REPLACING the remote collection. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_sync_upload(
    col_path: *const c_char,
    hkey: *const c_char,
) -> c_int {
    let col_path = match unsafe { cstr_to_string(col_path) } {
        Some(p) => p,
        None => {
            set_last_error("null col path".into());
            return 1;
        }
    };
    let hkey = match unsafe { cstr_to_string(hkey) } {
        Some(h) => h,
        None => {
            set_last_error("null hkey".into());
            return 1;
        }
    };
    sync_log_reset();
    sync_log("op=upload");
    let col = match CollectionBuilder::new(PathBuf::from(&col_path)).build() {
        Ok(c) => c,
        Err(e) => {
            set_last_error(format!("open failed: {e}"));
            return 2;
        }
    };
    let rt = match sync_runtime() {
        Ok(r) => r,
        Err(e) => {
            set_last_error(format!("runtime: {e}"));
            return 2;
        }
    };
    let auth = SyncAuth {
        hkey,
        endpoint: None,
        io_timeout_secs: None,
    };
    // Same endpoint discovery as download: issue the upload directly to the
    // assigned host so redirects don't drop the anki-original-size header.
    let local_meta = match col.sync_meta() {
        Ok(m) => m,
        Err(e) => {
            set_last_error(format!("sync_meta failed: {e:?}"));
            return 2;
        }
    };
    let mut client = HttpSyncClient::new(auth.clone(), sync_client());
    let state = match rt.block_on(online_sync_status_check(local_meta, &mut client)) {
        Ok(s) => s,
        Err(e) => {
            sync_log(format!("error_category={}", error_category(&e)));
            set_last_error(format!("sync status check failed: {e:?}"));
            return 2;
        }
    };
    let mut upload_auth = auth;
    if let Some(ep) = state.new_endpoint.as_deref() {
        match reqwest::Url::parse(ep) {
            Ok(u) => upload_auth.endpoint = Some(u),
            Err(e) => {
                set_last_error(format!("server returned an invalid endpoint: {e}"));
                return 2;
            }
        }
    }
    sync_log(format!(
        "upload_endpoint={}",
        endpoint_host(upload_auth.endpoint.as_ref().map(|u| u.as_str()))
    ));
    match rt.block_on(col.full_upload(upload_auth, sync_client())) {
        Ok(()) => {
            sync_log("full_upload=ok");
            0
        }
        Err(e) => {
            sync_log("full_upload=err");
            sync_log(format!("error_category={}", error_category(&e)));
            set_last_error(format!("sync_upload failed: {e:?}"));
            2
        }
    }
}

/// Sync media files (download/upload the actual image/audio files) for `hkey`.
/// Uses the desktop media-folder convention (`<col>.media`). Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_sync_media(
    col_path: *const c_char,
    hkey: *const c_char,
) -> c_int {
    let col_path = match unsafe { cstr_to_string(col_path) } {
        Some(p) => p,
        None => {
            set_last_error("null col path".into());
            return 1;
        }
    };
    let hkey = match unsafe { cstr_to_string(hkey) } {
        Some(h) => h,
        None => {
            set_last_error("null hkey".into());
            return 1;
        }
    };
    let mut builder = CollectionBuilder::new(PathBuf::from(&col_path));
    builder.with_desktop_media_paths();
    let mut col = match builder.build() {
        Ok(c) => c,
        Err(e) => {
            set_last_error(format!("open failed: {e}"));
            return 2;
        }
    };
    let mgr = match col.media() {
        Ok(m) => m,
        Err(e) => {
            set_last_error(format!("media open failed: {e}"));
            let _ = col.close(None);
            return 2;
        }
    };
    let progress = col.new_progress_handler::<MediaSyncProgress>();
    let auth = SyncAuth {
        hkey,
        endpoint: None,
        io_timeout_secs: None,
    };
    let rt = match sync_runtime() {
        Ok(r) => r,
        Err(e) => {
            set_last_error(format!("runtime: {e}"));
            let _ = col.close(None);
            return 2;
        }
    };
    let result = rt.block_on(mgr.sync_media(progress, auth, sync_client(), None));
    let _ = col.close(None);
    match result {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(format!("sync_media failed: {e:?}"));
            2
        }
    }
}

/// Back up the whole collection to a `.colpkg` at `out_path` (with media).
/// Consumes/reopens internally (export closes the collection). Returns 0 on ok.
#[no_mangle]
pub extern "C" fn anki_backend_export_colpkg(
    col_path: *const c_char,
    out_path: *const c_char,
) -> c_int {
    let col_path = match unsafe { cstr_to_string(col_path) } {
        Some(p) => p,
        None => {
            set_last_error("null col path".into());
            return 1;
        }
    };
    let out_path = match unsafe { cstr_to_string(out_path) } {
        Some(p) => p,
        None => {
            set_last_error("null out path".into());
            return 1;
        }
    };
    let mut builder = CollectionBuilder::new(PathBuf::from(&col_path));
    builder.with_desktop_media_paths();
    let col = match builder.build() {
        Ok(c) => c,
        Err(e) => {
            set_last_error(format!("open failed: {e}"));
            return 2;
        }
    };
    match col.export_colpkg(&out_path, true, false) {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(format!("export_colpkg failed: {e:?}"));
            2
        }
    }
}

/// Restore a `.colpkg` at `colpkg_path`, REPLACING the collection at `col_path`
/// (and its media). Unlike .apkg import, this whole-collection restore avoids the
/// deck-merge conflict. Returns 0 on success.
#[no_mangle]
pub extern "C" fn anki_backend_import_colpkg(
    col_path: *const c_char,
    colpkg_path: *const c_char,
) -> c_int {
    let col_path = match unsafe { cstr_to_string(col_path) } {
        Some(p) => p,
        None => {
            set_last_error("null col path".into());
            return 1;
        }
    };
    let colpkg_path = match unsafe { cstr_to_string(colpkg_path) } {
        Some(p) => p,
        None => {
            set_last_error("null colpkg path".into());
            return 1;
        }
    };
    let target = PathBuf::from(&col_path);
    let media_folder = target.with_extension("media");
    let media_db = target.with_extension("mdb");
    let _ = std::fs::create_dir_all(&media_folder);
    // Open the target only to obtain a progress handler (it clones an Arc, so it
    // stays valid after close), then close so import can replace the file.
    let col = match CollectionBuilder::new(target.clone()).build() {
        Ok(c) => c,
        Err(e) => {
            set_last_error(format!("open failed: {e}"));
            return 2;
        }
    };
    let progress = col.new_progress_handler::<ImportProgress>();
    if let Err(e) = col.close(None) {
        set_last_error(format!("close failed: {e}"));
        return 2;
    }
    match import_colpkg(&colpkg_path, &col_path, &media_folder, &media_db, progress) {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(format!("import_colpkg failed: {e:?}"));
            2
        }
    }
}

// ─── Test support (used only by integration tests) ────────────────────────────

/// Create a deterministic fixture collection at `path` (must not already exist).
/// Contains: two top-level decks + one subdeck, Hebrew RTL HTML, mixed LTR,
/// MathJax, tags, and cards in new / learning / review states.
#[no_mangle]
pub extern "C" fn anki_backend_create_fixture(path: *const c_char) -> c_int {
    let path = match unsafe { cstr_to_string(path) } {
        Some(p) => p,
        None => {
            set_last_error("null path".into());
            return 1;
        }
    };
    match build_fixture(&path) {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(format!("create_fixture failed: {e}"));
            2
        }
    }
}

fn build_fixture(path: &str) -> Result<()> {
    let mut col = CollectionBuilder::new(PathBuf::from(path)).build()?;

    let math = col.get_or_create_normal_deck("Math")?;
    let _lang = col.get_or_create_normal_deck("Languages")?;
    let heb = col.get_or_create_normal_deck("Languages::Hebrew")?;

    let nt = col
        .get_notetype_by_name("Basic")?
        .or_invalid("Basic notetype missing")?;

    // Hebrew RTL + MathJax + mixed LTR content (matches the AI prompt rules).
    let heb_notes = [
        (
            r#"<div dir="rtl" style="text-align: right;"><b>מהי קבוע פלאנק?</b></div>"#,
            r#"<div dir="rtl" style="text-align: right; line-height: 1.7;">קבוע פלאנק <span dir="ltr">\(h \approx 6.626\times10^{-34}\)</span><span dir="ltr"> J·s</span></div>"#,
            vec!["physics", "hebrew"],
        ),
        (
            r#"<div dir="rtl" style="text-align: right;"><b>שלום</b> פירושו?</div>"#,
            r#"<div dir="rtl" style="text-align: right;">hello / peace</div>"#,
            vec!["vocab"],
        ),
        (
            r#"<div dir="rtl" style="text-align: right;"><b>תרגום:</b> <span dir="ltr">book</span></div>"#,
            r#"<div dir="rtl" style="text-align: right;">ספר</div>"#,
            vec!["vocab"],
        ),
    ];
    for (front, back, tags) in heb_notes {
        add_note(&mut col, &nt, heb.id, front, back, &tags)?;
    }

    let math_notes = [
        (
            r#"<div>What is \(\int_0^1 x\,dx\)?</div>"#,
            r#"<div dir="ltr" style="text-align: center;">\[\frac{1}{2}\]</div>"#,
            vec!["calculus"],
        ),
        (
            r#"<div>Derivative of \(x^2\)?</div>"#,
            r#"<div>\(2x\)</div>"#,
            vec!["calculus"],
        ),
        (r#"<div>2 + 2 = ?</div>"#, r#"<div>4</div>"#, vec!["arithmetic"]),
        (r#"<div>3 × 3 = ?</div>"#, r#"<div>9</div>"#, vec!["arithmetic"]),
    ];
    for (front, back, tags) in math_notes {
        add_note(&mut col, &nt, math.id, front, back, &tags)?;
    }

    // Schedule a mix of states so counts are non-trivial:
    //   - one Math card → review due today (set_due_date "0")
    //   - one Math card → learning (grade Good now)
    //   - the rest stay new
    let math_cards = col.search_cards("deck:Math", SortMode::NoOrder)?;
    if let Some(review_card) = math_cards.first() {
        col.set_due_date(&[*review_card], "0", None)?;
    }
    if math_cards.len() > 1 {
        // Direct call uses grade_now's NATIVE 0-based scale (0=Again 1=Hard
        // 2=Good 3=Easy). Grading a new card here puts it into a short learning
        // step due today (counts toward learn_count) under classic and FSRS.
        col.grade_now(&[math_cards[1]], 1)?;
    }

    col.close(None)?;
    Ok(())
}

fn add_note(
    col: &mut Collection,
    nt: &Notetype,
    did: DeckId,
    front: &str,
    back: &str,
    tags: &[&str],
) -> Result<()> {
    let mut note = nt.new_note();
    note.set_field(0, front)?;
    note.set_field(1, back)?;
    note.tags = tags.iter().map(|s| s.to_string()).collect();
    col.add_note(&mut note, did)?;
    Ok(())
}
