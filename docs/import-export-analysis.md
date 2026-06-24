# Import / Export Analysis

## Finding
`.apkg` / `.colpkg` import/export is implemented by the Rust backend
(`libanki/.../BackendImportExport.kt` is a wrapper). It handles the zip container, the
embedded SQLite collection, the `media` map, and schema upgrades.

## iOS plan (M2)
- Reuse backend import/export through the Swift `libanki`-equivalent — guarantees round-trip
  compatibility with Anki Desktop / AnkiDroid / AnkiMobile.
- iOS entry points: Share-sheet / Files "Open in AnkiAI" for `.apkg`/`.colpkg`
  (`UTType` registration, `onOpenURL`), and export via the share sheet.

## Testing (M2)
Import→export→import round-trip on fixture `.apkg`s; verify note/card/media counts and that the
collection hash matches what the backend produces. Listed in CLAUDE.md testing requirements.

## Status
☐ Not started — depends on the backend (M2). No Swift import/export code claimed yet.
