#!/usr/bin/env bash
# Release desktop package for the current OS (rcs + stable).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${ROOT}/tools/flutter/bin:${PATH:-}"
unset CARGO_TARGET_DIR
CHANNEL="${HELMHOST_CHANNEL:-stable}"
VER="$(tr -d '[:space:]' <"$ROOT/VERSION")"
OUT="$ROOT/dist/${CHANNEL}"
mkdir -p "$OUT"
cd "$ROOT"
./scripts/hh-version sync --build "${GITHUB_RUN_NUMBER:-1}"
cargo build -p helmhost-ffi --release
cd "$ROOT/apps/client"
flutter pub get
case "$(uname -s)" in
  Darwin)
    flutter build macos --release
    ZIP="$OUT/helmhost-${CHANNEL}-macos-$(uname -m)-v${VER}.zip"
    ditto -c -k --sequesterRsrc --keepParent \
      build/macos/Build/Products/Release/helmhost_client.app "$ZIP"
    echo "wrote $ZIP"
    ;;
  Linux)
    flutter build linux --release
    TAR="$OUT/helmhost-${CHANNEL}-linux-x64-v${VER}.tar.gz"
    tar -C build/linux/x64/release/bundle -czf "$TAR" .
    echo "wrote $TAR"
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    flutter build windows --release
    ZIP="$OUT/helmhost-${CHANNEL}-windows-x64-v${VER}.zip"
    (cd build/windows/x64/runner/Release && zip -r "$ZIP" .)
    echo "wrote $ZIP"
    ;;
  *)
    echo "unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac
