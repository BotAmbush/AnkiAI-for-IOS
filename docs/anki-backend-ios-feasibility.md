# Anki Rust Backend on iOS — Feasibility (Phase A)

**Decision: GO — proven by CI.**

The pinned upstream Anki Rust backend (`ankitects/anki` `25.09.2`, commit
`3890e12c…`) compiles for both required iOS targets through our narrow C-ABI
bridge crate. No fundamental architecture or licensing *blocker* was found
(licensing is an obligation, not a blocker — see below).

## Evidence (actual CI results)

| Run | Commit | Result | Note |
|---|---|---|---|
| `28098142115` | `ee69e01` | fail | `anki_i18n` build script could not find Fluent `.ftl` — `--depth 1` clone omitted the `ftl/core-repo` submodule. |
| `28098435865` | `d80ed42` | fail | After adding submodules, `anki` failed to compile standalone: `unresolved import tokio::io::AsyncReadExt`. anki declares `tokio` **without** `io-util`; that feature is normally turned on transitively. |
| `28099025800` | `8aa5b3a` | **success** | Built the bridge crate (which enables `tokio/io-util` via feature unification) for **both** `aarch64-apple-ios` and `aarch64-apple-ios-sim`. Log: `SPIKE OK: bridge + anki compiled for aarch64-apple-ios aarch64-apple-ios-sim`. |

Build environment: GitHub `macos-15-arm64`, Xcode 16.4, Rust `1.89.0` (pinned),
`protoc` (libprotoc 35.0). `anki` compiled in ~2–3 min per target.

## What made it work (root causes + fixes)

1. **Submodules**: clone anki with `--recurse-submodules --shallow-submodules`
   so `rslib/i18n/gather.rs` finds translations in `ftl/core-repo`.
2. **tokio `io-util`**: anki's `Cargo.toml` declares
   `tokio = { features = ["fs","rt-multi-thread","macros","signal"] }` — no
   `io-util`, which its `async-compression`/`StreamReader` code needs. Building
   *through our bridge crate*, which adds `tokio = { features = ["io-util"] }`,
   enables it for the whole graph (additive feature unification) without
   modifying the pinned anki source.
3. **protoc** installed on the runner for `anki_proto`'s build script.
4. No TLS feature enabled (sync unused for the read path), avoiding extra crypto
   build complexity (`aws-lc-rs`/`ring`/`native-tls`) on iOS for now.

## Comparison of approaches considered (for the record)

| Approach | Verdict |
|---|---|
| **Compile the necessary crates via a narrow C-ABI bridge** (chosen) | ✅ Works. Reuses the canonical scheduler/FSRS/DB/sync; minimal surface; pinned & reproducible. |
| Patch the upstream Rust backend | ❌ Avoided. Would fork the pin and complicate updates. The two issues were solved *without* patching anki (submodules in the clone; `io-util` via our crate). |
| Compile only a subset of crates | ❌ Not separable. `anki` (rslib) is a single crate; you build it whole. |
| Alternative compatible backend | ❌ Unnecessary and would risk data/sync compatibility. |
| Limited Swift collection reader (re-implement schema in Swift) | ❌ Rejected (DL-001): high risk to data/sync compatibility; large effort; the canonical backend already works. |

## Licensing (obligation, not a blocker)

Linking `anki` makes the shipped binary a combined work under **AGPL-3.0-or-later**.
This is an obligation to satisfy before any distribution beyond private sideloading
(provide corresponding source / offer; the repo is already source-available). See
`docs/licensing-analysis.md`. It does not block development.

## Consequence

Proceed to Phase B (assemble `AnkiCore.xcframework`), Phase C (fixture +
integration tests), and Phase D (wire `BackendCollectionGateway` into the app).
