#!/usr/bin/env bash
# Copy helmhost-ffi into the Flutter desktop build output for the current OS.
# Usage: copy_ffi_into_bundle.sh <debug|release> <bundle-or-runner-dir>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${1:-release}"
DEST_DIR="${2:-}"

if [[ -z "$DEST_DIR" ]]; then
  echo "usage: $0 <debug|release> <dest-dir>" >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin)
    NAME="libhelmhost_ffi.dylib"
    ;;
  Linux)
    NAME="libhelmhost_ffi.so"
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    NAME="helmhost_ffi.dll"
    ;;
  *)
    echo "unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

SRC=""
for cand in \
  "$ROOT/target/${PROFILE}/${NAME}" \
  "${CARGO_TARGET_DIR:-}/$PROFILE/${NAME}" \
  "$ROOT/target/debug/${NAME}" \
  "${CARGO_TARGET_DIR:-}/debug/${NAME}"; do
  if [[ -n "$cand" && -f "$cand" ]]; then
    SRC="$cand"
    break
  fi
done

if [[ -z "$SRC" ]]; then
  echo "error: missing $NAME — run: cargo build -p helmhost-ffi${PROFILE:+ --$PROFILE}" >&2
  echo "  looked under $ROOT/target/${PROFILE}/" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
cp -f "$SRC" "$DEST_DIR/$NAME"
echo "Embedded $SRC → $DEST_DIR/$NAME"

# Linux Flutter RPATH is $ORIGIN/lib — also place beside lib/ for dlopen by basename.
if [[ "$(uname -s)" == Linux ]]; then
  mkdir -p "$DEST_DIR/lib"
  cp -f "$SRC" "$DEST_DIR/lib/$NAME"
  echo "Embedded $SRC → $DEST_DIR/lib/$NAME"
fi
