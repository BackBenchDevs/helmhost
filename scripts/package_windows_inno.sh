#!/usr/bin/env bash
# Build upgradeable Windows setup.exe via Inno Setup (fixed AppId).
# Usage: package_windows_inno.sh <runner-Release-dir> <out-dir> <version> <channel>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-}"
OUT_DIR="${2:-}"
VER="${3:-}"
CHANNEL="${4:-stable}"
ISS="$ROOT/packaging/windows/helmhost.iss"

if [[ -z "$SRC" || -z "$OUT_DIR" || -z "$VER" ]]; then
  echo "usage: $0 <Release-dir> <out-dir> <version> [channel]" >&2
  exit 1
fi
if [[ ! -d "$SRC" ]]; then
  echo "error: missing source dir: $SRC" >&2
  exit 1
fi
if [[ ! -f "$ISS" ]]; then
  echo "error: missing $ISS" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

find_iscc() {
  if command -v ISCC.exe >/dev/null 2>&1; then
    command -v ISCC.exe
    return
  fi
  if command -v iscc >/dev/null 2>&1; then
    command -v iscc
    return
  fi
  local cand
  for cand in \
    "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
    "/c/Program Files/Inno Setup 6/ISCC.exe" \
    "C:/Program Files (x86)/Inno Setup 6/ISCC.exe" \
    "C:/Program Files/Inno Setup 6/ISCC.exe"; do
    if [[ -x "$cand" || -f "$cand" ]]; then
      echo "$cand"
      return
    fi
  done
  return 1
}

ISCC="$(find_iscc)" || {
  echo "error: Inno Setup (ISCC.exe) not found — install Inno Setup 6" >&2
  exit 1
}

# Inno wants Windows-style paths when possible
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

SRC_W="$(win_path "$(cd "$SRC" && pwd)")"
OUT_W="$(win_path "$(cd "$OUT_DIR" && pwd)")"
ISS_W="$(win_path "$ISS")"

"$ISCC" \
  "//DMyAppVersion=${VER}" \
  "//DMyAppChannel=${CHANNEL}" \
  "//DMySourceDir=${SRC_W}" \
  "//DMyOutDir=${OUT_W}" \
  "$ISS_W"

SETUP="$OUT_DIR/helmhost-${CHANNEL}-windows-x64-v${VER}-setup.exe"
if [[ ! -f "$SETUP" ]]; then
  echo "error: expected $SETUP after ISCC" >&2
  ls -la "$OUT_DIR" >&2 || true
  exit 1
fi
echo "wrote $SETUP"
