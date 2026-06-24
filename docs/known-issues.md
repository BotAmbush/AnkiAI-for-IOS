# Known Issues / Honest Limitations

Updated 2026-06-24 (M1).

## Not yet built (by design — milestoned)
- **No real Anki collection yet.** M1 runs on an in-memory `StubCollectionGateway`. Decks,
  counts, the review queue, answer buttons, browser, editor, stats, scheduler/FSRS, sync, and
  import/export all arrive with the Rust backend in **M2**. Nothing here claims otherwise.
- **AI Insights uses sample stats.** The tip *engine* is real and tested; live numbers need
  revlog reads (M2).
- **Creator attachments (photo/PDF) UI not wired.** The client/model support images and are
  tested; the SwiftUI picker + PDFKit rasterization are pending.
- **Forced-study mode not ported.** iOS platform limits mean partial parity (see migration-risks R2). M3.

## Build / CI
- **The macOS Xcode build has not been run yet** — the dev machine is Windows. The app is *not*
  confirmed to compile, and no IPA exists, until the GitHub Actions workflow runs green and uploads
  the artifact. This is the immediate next step and requires the user to trigger the workflow (or
  authorize `gh`). Per CLAUDE.md, no "it compiles" / "IPA ready" claim is made before that.

## Rendering
- MathJax loads from a CDN (needs network) until bundled locally (DL-008).
- Card rendering shows raw fields/proposals; full template (qfmt/afmt) + CSS rendering is M2.

## Licensing
- AGPL implications of distributing the Rust `anki` backend must be resolved before any binary
  release (licensing-analysis.md open item).
