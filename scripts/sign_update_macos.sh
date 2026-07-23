#!/usr/bin/env bash
# Sign a macOS update zip with Sparkle Ed25519 private key (CI).
# Usage: sign_update_macos.sh <zip> <ed25519-private-key-file>
# Prints: <edSignature> <length>
set -euo pipefail
ZIP="${1:?zip}"
KEY="${2:?ed25519 private key file}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/apps/client/macos/Pods/Sparkle/bin/sign_update"
if [[ ! -x "$BIN" ]]; then
  echo "error: missing $BIN — run pod install in apps/client/macos" >&2
  exit 1
fi
SIG="$("$BIN" --account helmhost --ed-key-file "$KEY" -p "$ZIP" | tr -d '\n')"
LEN="$(wc -c <"$ZIP" | tr -d ' ')"
printf '%s %s\n' "$SIG" "$LEN"
