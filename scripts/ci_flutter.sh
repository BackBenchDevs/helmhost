#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${ROOT}/tools/flutter/bin:${PATH:-}"
unset CARGO_TARGET_DIR
cd "$ROOT"
./scripts/hh-version sync --build "${GITHUB_RUN_NUMBER:-1}"
cargo build -p helmhost-ffi --release
cd "$ROOT/apps/client"
flutter pub get
flutter analyze
flutter test
echo "ci_flutter: OK"
