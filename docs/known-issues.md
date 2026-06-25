# Known Issues / Honest Limitations

Updated 2026-06-24 (M1).

## 2026-06-25 device repair — resolved + awaiting retest
Three physical-device defects were fixed (code-complete, **not yet device-retested**):
- **Manual backup invisible in Files** — root cause was the missing Info.plist
  file-sharing keys, not the export. Now `UIFileSharingEnabled` +
  `LSSupportsOpeningDocumentsInPlace` (CI verifies both in the COMPILED app), and
  backups are validated + saved to `Documents/Backups` (Files-visible) with
  list/share/save/delete.
- **No discoverable manual Add Card** — added a native Decks-toolbar "+" → Basic/Cloze
  creator (real backend).
- **Logout did nothing / stale demo account** — auth state is now observable;
  demo/seeded is never shown as authenticated; Logout clears the session immediately.
Confirmed working on device and recorded device-verified: full download, media,
two-way sync, persistence, learning-delay, MathJax, demo-upload-block. Full **upload**
remains NOT device-verified (guarded).

## ⛔ BLOCKER (2026-06-24): GitHub Actions macOS minutes exhausted
After ~10+ full macOS builds in one day on the **private** repo (macOS minutes bill
at 10×), GitHub Actions began failing every job **instantly** (0 steps, ~3–6 s, no
logs / `BlobNotFound`) — runs `28127177086` and `28127347121`. The last green run was
M2.9 (`28125950705`). The workflow is unchanged; this is account-level **included-minutes
/ spending-limit exhaustion**, not a code error.

**Consequence:** the **M2.10** slice (`.apkg` export/import + round-trip test, commit
`aefdd72`) is **written and committed but UNVERIFIED** — it has never built. It must not
be treated as green until a macOS run passes.

**To unblock (user action — pick one):**
1. **Make the repo public** — public repos get unlimited free Actions minutes (the code is
   already GPL/AGPL; this is a product decision).
2. Add a payment method / raise the **Actions spending limit** (Settings → Billing).
3. Wait for the monthly minutes quota to reset.
Then re-run the workflow (`mode=full`) on `main` and drive the build-repair loop.

## AnkiWeb full-sync download — HTTP 400 "missing original size" (FIX in M2.29, pending device retest)
On a physical iPhone, login succeeded but one-way **Download from AnkiWeb** failed
with `HttpError { code: 400, context: "missing original size" }`. Root cause: the
bridge called `full_download` with `endpoint: None`, so the request hit the default
AnkiWeb host; AnkiWeb shards accounts per host, the default host **redirected**, and
the redirect dropped the `anki-original-size` request header → the assigned host
returned 400. Matches AnkiDroid **#14935** ("sync endpoint moved") and **#19102**
("full sync"). Fix: `sync_download`/`sync_upload` now run a meta request
(`online_sync_status_check` → `meta_with_redirect`) to discover the assigned endpoint
and persist it into `SyncAuth` before the transfer, so the request goes **directly**
to the right host (no header-dropping redirect). `full_download` already writes to a
temp file, integrity-checks it, and atomically renames — the local collection is
preserved on any failure. Sanitized diagnostics added (`anki_backend_take_sync_log`,
never logs key/password/headers/contents). **Status: code fix + offline regression
tests landed; awaiting a successful on-device download retest before marking
synchronization complete.**

## ⛳ OPEN TODO — card import from a collection file is NOT finished
Loading a user's existing collection via **file import (.apkg/.colpkg) is incomplete**
(see below). Per the user's direction, the current path to load a real collection is
**AnkiWeb sync** (M2.19+). File import remains an open TODO to revisit later.

## .apkg import — SAFE but happy-path blocked (audit M2)
`.apkg` import is now defence-in-depth SAFE: a pre-import `.colpkg` backup is
written and the merge runs in a backend transaction that rolls back on any
failure, so a malformed/incompatible package leaves the collection unchanged
(tested: malformed + missing package preserve all cards/decks). However the
HAPPY-PATH `.apkg` import still fails with an anki-internal `InvalidInput`
(`decks have different kinds`, rslib import_export/package/apkg/import/decks.rs:141)
where `update_deck` is reached for a same-kind deck yet neither normal nor
filtered branch matches. This needs LOCAL anki debugging (cannot run anki on the
Windows dev box). The WORKING package-import paths are `.colpkg` restore
(round-trip integration-tested) and AnkiWeb sync. import_export/apkg_colpkg stay
**partial**.

## M2.10/M2.18 import round-trip — needs local debugging
`.apkg` **export** works (verified: valid ZIP package). The export→**import**
round-trip into a *fresh* collection fails with an opaque anki `InvalidInput`
(previously surfaced as "decks have different kinds",
`import_export/package/apkg/import/decks.rs:141`). Tried **default** and
**with_scheduling + with_deck_configs** options (M2.18) — both fail. The error
message isn't propagated (the bridge now uses Debug format to capture it next
time). This is an anki-internal edge that needs **local** debugging (can't run
anki on the Windows dev box) or the **.colpkg restore** path (whole-collection
replace, which sidesteps deck merging). Import is wired but not asserted. Getting
a real user collection in (this or sync) is the top remaining gap.

## M2.1 status (verified 2026-06-24, run 28101322821)
- **Real Anki collection READ path works.** The app links the real Rust backend
  (`AnkiCore.xcframework`, anki 25.09.2) and the deck list shows real decks/subdecks with live
  new/learn/review counts. Verified by 3 integration tests + a green CI build + a 4.5 MB arm64 IPA.
- **Validation level:** fixture-based + Simulator (CI). **Not yet** validated on a physical
  device, and not against a user's real/synced collection.
- **Still stubbed / not implemented:** review queue, answer buttons, scheduler/FSRS UI, card
  browser, editor, statistics, filtered decks, import/export, backups, sync. Collection **write**
  paths (note add/update, card context) throw `GatewayError.notImplementedInM21` by design — the AI
  card-edit/add and creator-"add" actions therefore error until M2.2 wires writes to the backend.
- The production collection is seeded once on first launch via the backend (a real sample
  collection, not hardcoded data).
- **AI Insights uses sample stats.** The tip *engine* is real and tested; live numbers need
  revlog reads (M2).
- **Creator attachments (photo/PDF) UI not wired.** The client/model support images and are
  tested; the SwiftUI picker + PDFKit rasterization are pending.
- **Forced-study mode not ported.** iOS platform limits mean partial parity (see migration-risks R2). M3.

## Build / CI
- **The macOS Xcode build is green** (run `28097004935`): build SUCCEEDED, 38 unit tests passed on
  the Simulator, and an unsigned device IPA (`AnkiAI-unsigned.ipa`, Release `arm64`, in `Payload/`)
  was packaged and uploaded as a GitHub Actions artifact alongside diagnostics (logs, `.xcresult`,
  dSYMs). This is milestone 1 only — the IPA contains the AI layer + UI shell running against the
  in-memory collection stub; the Anki core arrives at M2.

## Rendering
- MathJax loads from a CDN (needs network) until bundled locally (DL-008).
- Card rendering shows raw fields/proposals; full template (qfmt/afmt) + CSS rendering is M2.

## Licensing
- AGPL implications of distributing the Rust `anki` backend must be resolved before any binary
  release (licensing-analysis.md open item).
