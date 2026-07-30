#!/usr/bin/env bash
# Build upgradeable Windows setup.exe via Inno Setup (fixed AppId).
# Usage: package_windows_inno.sh <runner-Release-dir> <out-dir> <version> <channel> [output-basename.exe]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-}"
OUT_DIR="${2:-}"
VER="${3:-}"
CHANNEL="${4:-stable}"
OUT_BASENAME="${5:-}"
ISS="$ROOT/packaging/windows/helmhost.iss"

if [[ -z "$SRC" || -z "$OUT_DIR" || -z "$VER" ]]; then
  echo "usage: $0 <Release-dir> <out-dir> <version> [channel] [output-basename.exe]" >&2
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

if [[ -z "$OUT_BASENAME" ]]; then
  OUT_BASENAME="$("$ROOT/scripts/artifact_basename.sh" \
    --os windows --arch x64 --ext exe --setup --channel "$CHANNEL" --ver "$VER")"
fi
# Inno OutputBaseFilename is without .exe
OUT_BASE="${OUT_BASENAME%.exe}"

CODENAME="$("$ROOT/scripts/hh-version" show --json 2>/dev/null \
  | sed -n 's/.*"release_tag":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
CODENAME="$(printf '%s' "${CODENAME:-lantern}" | tr '[:upper:]' '[:lower:]')"

RC_SUFFIX=""
RC="${HELMHOST_RC:-}"
if [[ -z "$RC" && -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_NAME}" =~ -rc\.([0-9]+)$ ]]; then
  RC="${BASH_REMATCH[1]}"
fi
if [[ -n "$RC" ]]; then
  RC_SUFFIX="-rc.${RC}"
fi

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

win_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
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
  "//DMyAppCodename=${CODENAME}" \
  "//DMyAppRcSuffix=${RC_SUFFIX}" \
  "//DMyOutputBase=${OUT_BASE}" \
  "//DMySourceDir=${SRC_W}" \
  "//DMyOutDir=${OUT_W}" \
  "$ISS_W"

SETUP="$OUT_DIR/${OUT_BASENAME}"
if [[ ! -f "$SETUP" ]]; then
  # Fallback if Inno ignored MyOutputBase
  SETUP_ALT="$OUT_DIR/helmhost-${CHANNEL}-windows-x64-${CODENAME}-v${VER}${RC_SUFFIX}-setup.exe"
  if [[ -f "$SETUP_ALT" ]]; then
    SETUP="$SETUP_ALT"
  else
    echo "error: expected $SETUP after ISCC" >&2
    ls -la "$OUT_DIR" >&2 || true
    exit 1
  fi
fi
echo "wrote $SETUP"
