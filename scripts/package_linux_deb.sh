#!/usr/bin/env bash
# Build upgradeable .deb (same package name → dpkg upgrades).
# Usage: package_linux_deb.sh <bundle-dir> <out-deb> <version> <channel>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="${1:-}"
OUT_DEB="${2:-}"
VER="${3:-}"
CHANNEL="${4:-stable}"
ARCH="amd64"
PKG_NAME="helmhost"

if [[ -z "$BUNDLE" || -z "$OUT_DEB" || -z "$VER" ]]; then
  echo "usage: $0 <linux-bundle-dir> <out.deb> <version> [channel]" >&2
  exit 1
fi
if [[ ! -d "$BUNDLE" ]]; then
  echo "error: missing bundle: $BUNDLE" >&2
  exit 1
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/helmhost-deb.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$STAGE/DEBIAN"
"$ROOT/scripts/package_linux_stage.sh" "$BUNDLE" "$STAGE" "$CHANNEL"

INSTALLED_SIZE="$(du -sk "$STAGE/opt" "$STAGE/usr" | awk '{s+=$1} END {print s}')"

cat >"$STAGE/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VER}
Section: net
Priority: optional
Architecture: ${ARCH}
Maintainer: BackBenchDevs <noreply@bbdevs.com>
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, liblzma5
Homepage: https://github.com/BackBenchDevs/helmhost
Description: Open multi-session RFB / VNC viewer
 Helmhost desktop client (${CHANNEL} channel).
 Reinstalling a newer Version upgrades in place (same package name).
EOF

cat >"$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

cat >"$STAGE/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postrm"

mkdir -p "$(dirname "$OUT_DEB")"
dpkg-deb --build --root-owner-group "$STAGE" "$OUT_DEB"
echo "wrote $OUT_DEB"
