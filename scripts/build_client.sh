#!/usr/bin/env bash
# Local debug FFI build + analyze (does not launch the app).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${ROOT}/tools/flutter/bin:${PATH:-}"
unset CARGO_TARGET_DIR
cd "$ROOT"
cargo build -p helmhost-ffi
chmod +x apps/client/macos/Runner/Scripts/copy_ffi.sh 2>/dev/null || true
cd apps/client
flutter pub get
flutter analyze
echo "OK: ${ROOT}/target/debug/libhelmhost_ffi.dylib (or .so/.dll)"
echo "Run: cd apps/client && flutter run -d macos"
