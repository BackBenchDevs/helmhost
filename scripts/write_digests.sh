#!/usr/bin/env bash
# Write SHA-256 digests for release artifacts in a directory.
# Creates:
#   <dir>/SHA256SUMS              — all digests (basename paths)
#   <dir>/<artifact>.sha256       — one line each (for sidecars)
#
# Usage: write_digests.sh <dist-dir>
set -euo pipefail

DIR="${1:-}"
if [[ -z "$DIR" || ! -d "$DIR" ]]; then
  echo "usage: $0 <dist-dir>" >&2
  exit 1
fi

DIR="$(cd "$DIR" && pwd)"
SUMS="$DIR/SHA256SUMS"
rm -f "$SUMS"
: >"$SUMS"

sha_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$@"
  else
    echo "error: need sha256sum or shasum" >&2
    exit 1
  fi
}

shopt -s nullglob
count=0
for f in "$DIR"/*; do
  base="$(basename "$f")"
  [[ -f "$f" ]] || continue
  case "$base" in
    SHA256SUMS|*.sha256) continue ;;
  esac
  # Only package-like artifacts
  case "$base" in
    *.zip|*.tar.gz|*.tgz|*.pkg|*.deb|*-setup.exe|*.exe) ;;
    *) continue ;;
  esac

  line="$(sha_cmd "$f")"
  # Normalize to "HASH  basename" (two spaces — GNU sha256sum style)
  hash="${line%% *}"
  printf '%s  %s\n' "$hash" "$base" >>"$SUMS"
  printf '%s  %s\n' "$hash" "$base" >"$DIR/${base}.sha256"
  count=$((count + 1))
  echo "digest: $base → $hash"
done

if [[ "$count" -eq 0 ]]; then
  echo "error: no artifacts to digest in $DIR" >&2
  rm -f "$SUMS"
  exit 1
fi

echo "wrote $SUMS ($count files)"
