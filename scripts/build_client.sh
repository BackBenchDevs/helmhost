#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${ROOT}/tools/flutter/bin:${PATH:-}"
# Keep artifacts in-repo so Xcode copy_ffi.sh finds them
unset CARGO_TARGET_DIR
cd "$ROOT"
cargo build -p helmhost-ffi
chmod +x apps/client/macos/Runner/Scripts/copy_ffi.sh
cd apps/client
flutter pub get
flutter analyze
echo "OK: ${ROOT}/target/debug/libhelmhost_ffi.dylib"
echo "Quit any running helmhost_client, then: cd apps/client && flutter run -d macos"
