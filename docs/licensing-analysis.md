# Licensing Analysis

## Inherited license
The Android project is **GPL-3.0** (AnkiDroid + the fork's AI code). A derived iOS port of GPL
code is itself GPL-3.0. This repository is therefore licensed **GPL-3.0**. See `LICENSES.md`,
`THIRD_PARTY_NOTICES.md`, and `COPYING` (to be added with the full GPL text).

Origin is not concealed: this is a port of AnkiDroid (`ankidroid/Anki-Android`) and the
`BotAmbush/Anki-Android-AI` fork. Conceptually-ported logic retains attribution in docs and code
comments.

## Components & licenses

| Component | Origin | License | Notes |
|---|---|---|---|
| AnkiAI iOS (this repo) | derived from AnkiDroid fork | GPL-3.0 | inherited |
| Rust `anki` backend (M2) | `ankitects/anki` | AGPL-3.0 (rslib) | **Action item**: confirm AGPL obligations before shipping; the official AnkiMobile is closed but Anki core is AGPL — review distribution terms. Tracked as a release blocker. |
| MathJax | mathjax.org | Apache-2.0 | bundling planned (DL-008) |
| XcodeGen (build-time only) | yonaskolb/XcodeGen | MIT | not shipped in the app |
| System `libsqlite3` | Apple SDK | platform | no third-party SQLite package |
| Anthropic API | Anthropic | service (no bundled code) | key required, billed by Anthropic |

## Dependency policy (CLAUDE.md)
Before adding any iOS dependency: check maintenance, license compatibility, iOS support, and
whether a native API suffices. So far **zero** third-party Swift packages are bundled — the AI db
uses system SQLite and networking uses `URLSession` — keeping CI robust and the dependency surface
minimal.

## Open item
- [ ] Resolve AGPL implications of distributing the Rust `anki` backend in an iOS app before any
      public/binary release (R-license). Document the conclusion here and in `SECURITY.md`/README.
