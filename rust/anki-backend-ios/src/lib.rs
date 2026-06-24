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
use anki::search::SortMode;
use anki_proto::decks::DeckTreeNode;
use anki_proto::import_export::{ExportAnkiPackageOptions, ImportAnkiPackageOptions};
use anki_proto::scheduler::bury_or_suspend_cards_request::Mode as BuryOrSuspendMode;

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

fn set_last_error(msg: String) {
    LAST_ERROR.with(|e| *e.borrow_mut() = CString::new(msg).ok());
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
    // Default options (no media, current format); empty search = whole collection.
    match handle
        .col
        .export_apkg(&out_path, ExportAnkiPackageOptions::default(), "", None)
    {
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
    match handle
        .col
        .import_apkg(&in_path, ImportAnkiPackageOptions::default())
    {
        Ok(_) => 0,
        Err(e) => {
            set_last_error(format!("import_apkg failed: {e}"));
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
