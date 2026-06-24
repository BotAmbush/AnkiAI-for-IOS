# Known Issues / Honest Limitations

Updated 2026-06-24 (M1).

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
