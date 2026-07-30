#!/usr/bin/env bash
# Build Linux AppImage from Flutter release bundle via linuxdeploy.
# Usage: package_linux_appimage.sh <bundle-dir> <out.AppImage> <version> <channel>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="${1:-}"
OUT_APPIMAGE="${2:-}"
VER="${3:-}"
CHANNEL="${4:-stable}"
LINUXDEPLOY_VER="${LINUXDEPLOY_VERSION:-1-alpha-20251107-1}"

if [[ -z "$BUNDLE" || -z "$OUT_APPIMAGE" || -z "$VER" ]]; then
  echo "usage: $0 <linux-bundle-dir> <out.AppImage> <version> [channel]" >&2
  exit 1
fi
if [[ ! -d "$BUNDLE" ]]; then
  echo "error: missing bundle: $BUNDLE" >&2
  exit 1
fi
if [[ ! -x "$BUNDLE/helmhost" ]]; then
  echo "error: missing executable $BUNDLE/helmhost" >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/helmhost-appimage.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

ICON_SRC="$ROOT/apps/client/assets/brand/helmhost-icon-256.png"
[[ -f "$ICON_SRC" ]] || { echo "error: missing $ICON_SRC" >&2; exit 1; }
ICON_PNG="$WORK/helmhost.png"
cp "$ICON_SRC" "$ICON_PNG"

DESKTOP="$WORK/helmhost.desktop"
cat >"$DESKTOP" <<EOF
[Desktop Entry]
Name=Helmhost
Comment=Open multi-session RFB / VNC viewer
Exec=helmhost
Icon=helmhost
Terminal=false
Type=Application
Categories=Network;RemoteAccess;
X-AppImage-Version=${VER}
X-Helmhost-Channel=${CHANNEL}
EOF

if [[ -n "${LINUXDEPLOY_BIN:-}" && -x "${LINUXDEPLOY_BIN}" ]]; then
  LD="$LINUXDEPLOY_BIN"
else
  LD="$WORK/linuxdeploy-x86_64.AppImage"
  curl -fsSL \
    "https://github.com/linuxdeploy/linuxdeploy/releases/download/${LINUXDEPLOY_VER}/linuxdeploy-x86_64.AppImage" \
    -o "$LD"
  chmod +x "$LD"
fi

# Flutter expects lib/ and data/ beside the binary — keep that layout in AppDir.
APPDIR="$WORK/AppDir"
mkdir -p "$APPDIR"
cp -a "$BUNDLE"/. "$APPDIR/"

cd "$WORK"
export ARCH=x86_64
export VERSION="$VER"
"$LD" \
  --appdir "$APPDIR" \
  --executable "$APPDIR/helmhost" \
  --desktop-file "$DESKTOP" \
  --icon-file "$ICON_PNG" \
  --output appimage

shopt -s nullglob
FOUND=""
for c in "$WORK"/Helmhost*.AppImage "$WORK"/helmhost*.AppImage "$WORK"/*.AppImage; do
  # Skip the linuxdeploy tool itself
  base="$(basename "$c")"
  [[ "$base" == linuxdeploy* ]] && continue
  if [[ -f "$c" ]]; then
    FOUND="$c"
    break
  fi
done

if [[ -z "$FOUND" ]]; then
  echo "error: linuxdeploy did not produce an AppImage" >&2
  ls -la "$WORK" >&2 || true
  exit 1
fi

mkdir -p "$(dirname "$OUT_APPIMAGE")"
mv "$FOUND" "$OUT_APPIMAGE"
chmod 755 "$OUT_APPIMAGE"
test -f "$OUT_APPIMAGE"
echo "wrote $OUT_APPIMAGE"
