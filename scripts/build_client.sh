#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${ROOT}/tools/flutter/bin:${PATH}"
cd "$ROOT"
cargo build -p helmhost-ffi
cd apps/client
flutter pub get
flutter analyze
echo "OK: lib at ${ROOT}/target/debug/libhelmhost_ffi.dylib"
