#!/usr/bin/env bash
# Debug/profile desktop package for the current OS (portable only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${ROOT}/tools/flutter/bin:${PATH:-}"
unset CARGO_TARGET_DIR
CHANNEL="${HELMHOST_CHANNEL:-dev}"
SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo local)"
OUT="$ROOT/dist/${CHANNEL}"
mkdir -p "$OUT"
chmod +x "$ROOT"/scripts/*.sh 2>/dev/null || true

cd "$ROOT"
./scripts/hh-version sync --build "${GITHUB_RUN_NUMBER:-1}"
cargo build -p helmhost-ffi
cd "$ROOT/apps/client"
flutter pub get

win_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    # Git Bash: /c/foo → C:\foo
    if [[ "$p" =~ ^/([a-zA-Z])/(.*)$ ]]; then
      echo "${BASH_REMATCH[1]^}:\\${BASH_REMATCH[2]//\//\\}"
    else
      echo "$p"
    fi
  fi
}

zip_dir() {
  local src="$1" dest="$2"
  rm -f "$dest"
  if command -v zip >/dev/null 2>&1; then
    (cd "$src" && zip -r "$dest" .)
  elif command -v powershell.exe >/dev/null 2>&1; then
    local src_w dest_w
    src_w="$(win_path "$src")"
    dest_w="$(win_path "$dest")"
    powershell.exe -NoProfile -Command \
      "Compress-Archive -Path (Join-Path '$src_w' '*') -DestinationPath '$dest_w' -Force"
  else
    echo "error: need zip or powershell Compress-Archive" >&2
    exit 1
  fi
}

case "$(uname -s)" in
  Darwin)
    flutter build macos --debug
    APP="build/macos/Build/Products/Debug/helmhost.app"
    "$ROOT/scripts/copy_ffi_into_bundle.sh" debug "$ROOT/apps/client/${APP}/Contents/MacOS"
    ZIP="$OUT/helmhost-${CHANNEL}-macos-$(uname -m)-${SHA}.zip"
    ditto -c -k --sequesterRsrc --keepParent \
      "$ROOT/apps/client/${APP}" "$ZIP"
    echo "wrote $ZIP"
    "$ROOT/scripts/assert_ffi_in_artifact.sh" "$ZIP"
    ;;
  Linux)
    flutter build linux --debug
    BUNDLE="build/linux/x64/debug/bundle"
    "$ROOT/scripts/copy_ffi_into_bundle.sh" debug "$ROOT/apps/client/${BUNDLE}"
    TAR="$OUT/helmhost-${CHANNEL}-linux-x64-${SHA}.tar.gz"
    tar -C "$ROOT/apps/client/${BUNDLE}" -czf "$TAR" .
    echo "wrote $TAR"
    "$ROOT/scripts/assert_ffi_in_artifact.sh" "$TAR"
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    flutter build windows --debug
    REL="build/windows/x64/runner/Debug"
    "$ROOT/scripts/copy_ffi_into_bundle.sh" debug "$ROOT/apps/client/${REL}"
    ZIP="$OUT/helmhost-${CHANNEL}-windows-x64-${SHA}.zip"
    zip_dir "$ROOT/apps/client/${REL}" "$ZIP"
    echo "wrote $ZIP"
    "$ROOT/scripts/assert_ffi_in_artifact.sh" "$ZIP"
    ;;
  *)
    echo "unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

"$ROOT/scripts/write_digests.sh" "$OUT"

echo "artifacts in $OUT:"
ls -la "$OUT"
