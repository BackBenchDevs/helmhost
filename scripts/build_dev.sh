#!/usr/bin/env bash
# Debug/profile desktop package for the current OS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${ROOT}/tools/flutter/bin:${PATH:-}"
unset CARGO_TARGET_DIR
CHANNEL="${HELMHOST_CHANNEL:-dev}"
SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo local)"
OUT="$ROOT/dist/${CHANNEL}"
mkdir -p "$OUT"
cd "$ROOT"
./scripts/hh-version sync --build "${GITHUB_RUN_NUMBER:-1}"
cargo build -p helmhost-ffi
cd "$ROOT/apps/client"
flutter pub get
case "$(uname -s)" in
  Darwin)
    flutter build macos --debug
    ZIP="$OUT/helmhost-${CHANNEL}-macos-$(uname -m)-${SHA}.zip"
    ditto -c -k --sequesterRsrc --keepParent \
      build/macos/Build/Products/Debug/helmhost_client.app "$ZIP"
    echo "wrote $ZIP"
    ;;
  Linux)
    flutter build linux --debug
    TAR="$OUT/helmhost-${CHANNEL}-linux-x64-${SHA}.tar.gz"
    tar -C build/linux/x64/debug/bundle -czf "$TAR" .
    echo "wrote $TAR"
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    flutter build windows --debug
    ZIP="$OUT/helmhost-${CHANNEL}-windows-x64-${SHA}.zip"
    (cd build/windows/x64/runner/Debug && zip -r "$ZIP" .)
    echo "wrote $ZIP"
    ;;
  *)
    echo "unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac
