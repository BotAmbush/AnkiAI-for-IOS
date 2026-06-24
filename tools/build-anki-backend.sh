#!/usr/bin/env bash
#
# Deterministic build of the pinned upstream Anki Rust backend for iOS.
#
# Pin is recorded in docs/anki-backend-pin.md and mirrored here. This script must
# stay reproducible WITHOUT cache: a clean checkout + this script reproduces the
# same artifacts.
#
# Modes:
#   spike       (default) cargo-build the upstream `anki` crate for iOS targets to
#               prove it compiles. Produces no artifact beyond logs. This is the
#               Phase A feasibility gate.
#   xcframework Build the narrow C-ABI bridge crate (rust/anki-backend-ios) as a
#               static lib for each iOS target and assemble AnkiCore.xcframework.
#
# Usage:  tools/build-anki-backend.sh [spike|xcframework]
#
set -euo pipefail

# ─── Pin (keep in sync with docs/anki-backend-pin.md) ──────────────────────────
ANKI_REPO="https://github.com/ankitects/anki"
ANKI_TAG="25.09.2"
ANKI_COMMIT="3890e12c9e48c028c3f12aa58cb64bd9f8895e30"
RUST_TOOLCHAIN="1.89.0"

# iOS targets: device + simulator (arm64). (x86_64 sim intentionally omitted —
# GitHub macOS runners are arm64; add later if Intel-sim support is needed.)
TARGETS=("aarch64-apple-ios" "aarch64-apple-ios-sim")

MODE="${1:-spike}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/rust/.work"
ANKI_DIR="$WORK/anki"
OUT="$ROOT/build/backend"
mkdir -p "$WORK" "$OUT"

echo "== Anki backend build =="
echo "mode=$MODE  pin=$ANKI_TAG ($ANKI_COMMIT)  toolchain=$RUST_TOOLCHAIN"
echo "targets=${TARGETS[*]}"

# ─── Toolchain ────────────────────────────────────────────────────────────────
export RUSTUP_TOOLCHAIN="$RUST_TOOLCHAIN"
rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal
for t in "${TARGETS[@]}"; do
  rustup target add "$t" --toolchain "$RUST_TOOLCHAIN"
done

# protoc is required by anki_proto / anki build scripts.
if ! command -v protoc >/dev/null 2>&1; then
  echo "protoc not found on PATH" >&2
  exit 3
fi
export PROTOC="$(command -v protoc)"
echo "protoc: $PROTOC ($($PROTOC --version))"
echo "rustc:  $(rustc --version)"

# ─── Fetch pinned anki (immutable tag) ────────────────────────────────────────
# Submodules are required: rslib/i18n's build script reads Fluent translations
# from the ftl/core-repo submodule (gather.rs). Clone shallow with submodules.
if [ ! -d "$ANKI_DIR/.git" ]; then
  echo "Cloning anki @ $ANKI_TAG (with submodules) ..."
  git clone --depth 1 --branch "$ANKI_TAG" \
    --recurse-submodules --shallow-submodules "$ANKI_REPO" "$ANKI_DIR"
else
  git -C "$ANKI_DIR" submodule update --init --recursive --depth 1
fi
GOT="$(git -C "$ANKI_DIR" rev-parse HEAD)"
echo "anki HEAD: $GOT"
if [ "$GOT" != "$ANKI_COMMIT" ]; then
  echo "ERROR: anki HEAD $GOT != pinned $ANKI_COMMIT" >&2
  exit 4
fi

# Record backend metadata for the build artifacts.
cat > "$OUT/backend-metadata.txt" <<EOF
anki_repo=$ANKI_REPO
anki_tag=$ANKI_TAG
anki_commit=$ANKI_COMMIT
rust_toolchain=$RUST_TOOLCHAIN
rustc=$(rustc --version)
protoc=$($PROTOC --version)
targets=${TARGETS[*]}
mode=$MODE
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

BRIDGE="$ROOT/rust/anki-backend-ios"
[ -d "$BRIDGE" ] || { echo "bridge crate missing: $BRIDGE" >&2; exit 5; }

# Build the narrow C-ABI bridge static lib for each iOS target. This compiles the
# pinned `anki` crate transitively; the bridge enables tokio's io-util feature so
# anki's media/sync code compiles (see Cargo.toml).
LIBS=()
for t in "${TARGETS[@]}"; do
  # anki's build.rs reads anki_descriptors.bin produced by anki_proto's build
  # script. Cargo's DAG does not capture that implicit file dependency, so anki's
  # build script can race ahead of anki_proto's (flaky ENOENT). Build anki_proto
  # FIRST per target to generate the descriptor deterministically.
  echo "── cargo build -p anki_proto --target $t --release (descriptor) ──"
  ( cd "$BRIDGE" && cargo +"$RUST_TOOLCHAIN" build -p anki_proto --release --target "$t" \
      2>&1 | tee "$OUT/anki_proto-build-$t.log" )

  echo "── cargo build (bridge) --target $t --release ──"
  ( cd "$BRIDGE" && cargo +"$RUST_TOOLCHAIN" build --release --target "$t" \
      2>&1 | tee "$OUT/bridge-build-$t.log" )
  LIBS+=("$BRIDGE/target/$t/release/libanki_backend_ios.a")
done

if [ "$MODE" = "spike" ]; then
  echo "SPIKE OK: bridge + anki compiled for ${TARGETS[*]}"
  exit 0
fi

if [ "$MODE" = "xcframework" ]; then
  XCF="$ROOT/Frameworks/AnkiCore.xcframework"
  rm -rf "$XCF"; mkdir -p "$ROOT/Frameworks"
  HEADERS="$BRIDGE/include"
  ARGS=()
  for lib in "${LIBS[@]}"; do ARGS+=(-library "$lib" -headers "$HEADERS"); done
  xcodebuild -create-xcframework "${ARGS[@]}" -output "$XCF"
  echo "Built $XCF"
  exit 0
fi

echo "unknown mode: $MODE (use spike|xcframework)" >&2
exit 2
