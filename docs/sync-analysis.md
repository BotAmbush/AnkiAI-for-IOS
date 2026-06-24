# Sync Analysis

## Finding
AnkiWeb sync (and self-hosted sync) is implemented in the Rust `anki` backend: the HTTP
protocol, chunking, media sync, and conflict/full-sync handling. The fork explicitly leaves
sync untouched ("100% compatible with AnkiWeb sync and Anki Desktop") and adds no sync code.

## iOS plan (M2)
- Drive sync through the backend (`col.sync_login`, `col.sync_collection`, media sync) via the
  Swift wrapper — same protocol, same compatibility.
- Credentials (AnkiWeb token / endpoint) stored in **Keychain**.
- UI: a Sync action + status, full-sync direction prompt on conflict (matching desktop/AnkiDroid).

## Compatibility guarantee
Because we reuse the backend and never alter the schema, a collection can move between AnkiAI
(iOS), AnkiDroid, Anki Desktop, and AnkiMobile without data loss — the same guarantee the fork
makes on Android.

## Status
☐ Not started — backend-dependent (M2). No sync claims until the backend round-trips against a
test sync server.
