#!/usr/bin/env bash
# Build upgradeable macOS .pkg (fixed pkg id → upgrades via installer).
# Usage: package_macos_pkg.sh <app-path> <out-pkg> <version>
set -euo pipefail

APP="${1:-}"
OUT_PKG="${2:-}"
VER="${3:-}"
ID="dev.helmhost.client"

if [[ -z "$APP" || -z "$OUT_PKG" || -z "$VER" ]]; then
  echo "usage: $0 <Helmhost.app|helmhost.app> <out.pkg> <version>" >&2
  exit 1
fi
if [[ ! -d "$APP" ]]; then
  echo "error: missing app bundle: $APP" >&2
  exit 1
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/helmhost-pkg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$STAGE"
# Install as Helmhost.app under /Applications
ditto "$APP" "$STAGE/Helmhost.app"

pkgbuild \
  --root "$STAGE" \
  --identifier "$ID" \
  --version "$VER" \
  --install-location /Applications \
  "$OUT_PKG"

echo "wrote $OUT_PKG (id=$ID version=$VER)"
