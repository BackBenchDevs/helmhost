#!/usr/bin/env bash
# Build upgradeable .rpm via nfpm (mirrors DEB /opt layout).
# Usage: package_linux_rpm.sh <bundle-dir> <out-rpm> <version> <channel>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$ROOT/packaging/linux"
BUNDLE="${1:-}"
OUT_RPM="${2:-}"
VER="${3:-}"
CHANNEL="${4:-stable}"

if [[ -z "$BUNDLE" || -z "$OUT_RPM" || -z "$VER" ]]; then
  echo "usage: $0 <linux-bundle-dir> <out.rpm> <version> [channel]" >&2
  exit 1
fi
if [[ ! -d "$BUNDLE" ]]; then
  echo "error: missing bundle: $BUNDLE" >&2
  exit 1
fi
if ! command -v nfpm >/dev/null 2>&1; then
  echo "error: nfpm not found on PATH" >&2
  exit 1
fi

# Debian/RPM prefer ~ for prerelease; keep plain X.Y.Z for package Version.
export VERSION="$VER"

STAGE="$PKG_DIR/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
"$ROOT/scripts/package_linux_stage.sh" "$BUNDLE" "$STAGE" "$CHANNEL"

# Ensure icon paths exist so nfpm contents resolve
ICON="$STAGE/usr/share/icons/hicolor/256x256/apps/helmhost.png"
if [[ ! -f "$ICON" ]]; then
  echo "error: missing packaged icon at $ICON" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_RPM")"
cd "$PKG_DIR"
nfpm package --packager rpm --config nfpm.yaml --target "$OUT_RPM"
echo "wrote $OUT_RPM"
