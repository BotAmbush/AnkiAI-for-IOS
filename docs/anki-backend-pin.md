# Anki Rust Backend — Pinned Version

This file records the exact upstream Anki backend the iOS port targets. It is the
single source of truth for the pin; CI reads the same commit.

## Pin (immutable)

| Item | Value |
|---|---|
| Upstream repository | `https://github.com/ankitects/anki` |
| Release tag | `25.09.2` |
| **Pinned commit** | **`3890e12c9e48c028c3f12aa58cb64bd9f8895e30`** |
| Tag date | 2025-09-17 |
| Rust crate of interest | `anki` (path `rslib/`) |
| Rust toolchain (pinned by repo `rust-toolchain.toml`) | `1.89.0` |
| Workspace license | **AGPL-3.0-or-later** |

This is a **tag commit**, not a moving branch (satisfies the "no unpinned moving
branch" requirement).

## How this pin was derived (verified via GitHub API)

The Android fork depends on `io.github.david-allison:anki-android-backend`
version `0.1.64-anki25.09.2` (from `gradle/libs.versions.toml`). That backend
(`ankidroid/Anki-Android-Backend`) embeds upstream `anki` as a git submodule.

- `0.1.64-anki25.09.2` is not a public tag yet; the nearest published tags are
  `0.1.63-anki25.09.2` and `0.1.62-anki25.09.2`, all sharing the `anki25.09.2`
  upstream base.
- At backend tag `0.1.63-anki25.09.2`, the `anki` submodule gitlink resolves to
  commit `3890e12c9e48c028c3f12aa58cb64bd9f8895e30`.
- Independently, upstream `ankitects/anki` annotated tag `25.09.2` dereferences to
  the same commit `3890e12c9e48c028c3f12aa58cb64bd9f8895e30`.

Both paths agree, so the upstream pin is unambiguous.

> If/when `anki-android-backend` publishes `0.1.64-anki25.09.2` with a different
> `anki` submodule commit, re-verify and update this file. The `anki25.09.2`
> suffix indicates the upstream base remains Anki 25.09.2.

## Workspace layout (at the pinned commit)

`anki` (`rslib/`) is the library crate. Relevant sibling crates in the workspace:
`rslib/i18n` (`anki_i18n`, Fluent/.ftl), `rslib/io` (`anki_io`),
`rslib/proto` + `rslib/proto_gen` (`anki_proto*`, protobuf codegen),
`rslib/sync` (sync protocol), `rslib/process`.

### `anki` crate features (none enabled by default)
- `rustls` → `reqwest/rustls-tls`
- `native-tls` → `reqwest/native-tls`
- `bench`

### Build-time requirements (verified from `Cargo.toml`)
- `protoc` (protobuf compiler) — `anki`'s `build.rs` + `anki_proto` generate Rust
  from `.proto`. CI installs it via Homebrew and exports `PROTOC`.
- Build-deps run on the **host** (macOS) during cross-compile: `prost`,
  `prost-reflect`, `prettyplease`, `syn`, `anki_proto_gen` — codegen only.
- Network/TLS deps (`reqwest`, `axum`, `hyper`) are compiled but only exercised by
  sync, which M2.1 does not use.

## Licensing consequence

Linking `anki` makes the shipped app a combined work under **AGPL-3.0-or-later**
(stronger than the GPL-3.0 already inherited from AnkiDroid). See
`docs/licensing-analysis.md` for obligations and the open release-blocker item.
