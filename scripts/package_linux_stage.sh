#!/usr/bin/env bash
# Shared Linux install tree for DEB / RPM: /opt/helmhost + wrapper + desktop + icon.
# Usage: package_linux_stage.sh <bundle-dir> <stage-root> <channel>
# Writes into <stage-root> (caller owns temp dir / cleanup).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="${1:-}"
STAGE="${2:-}"
CHANNEL="${3:-stable}"

if [[ -z "$BUNDLE" || -z "$STAGE" ]]; then
  echo "usage: $0 <linux-bundle-dir> <stage-root> [channel]" >&2
  exit 1
fi
if [[ ! -d "$BUNDLE" ]]; then
  echo "error: missing bundle: $BUNDLE" >&2
  exit 1
fi

OPT="$STAGE/opt/helmhost"
mkdir -p "$OPT" \
  "$STAGE/usr/bin" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/256x256/apps" \
  "$STAGE/usr/share/pixmaps"

cp -a "$BUNDLE"/. "$OPT/"

cat >"$STAGE/usr/bin/helmhost" <<'EOF'
#!/bin/sh
exec /opt/helmhost/helmhost "$@"
EOF
chmod 755 "$STAGE/usr/bin/helmhost"
chmod 755 "$OPT/helmhost" 2>/dev/null || true

ICON_SRC="$ROOT/apps/client/assets/brand/helmhost-icon-256.png"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$STAGE/usr/share/icons/hicolor/256x256/apps/helmhost.png"
  cp "$ICON_SRC" "$STAGE/usr/share/pixmaps/helmhost.png"
fi

cat >"$STAGE/usr/share/applications/helmhost.desktop" <<EOF
[Desktop Entry]
Name=Helmhost
Comment=Open multi-session RFB / VNC viewer
Exec=/usr/bin/helmhost
Icon=helmhost
Terminal=false
Type=Application
Categories=Network;RemoteAccess;
X-Helmhost-Channel=${CHANNEL}
EOF
