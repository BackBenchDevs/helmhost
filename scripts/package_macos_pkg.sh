#!/usr/bin/env bash
# Build upgradeable macOS .pkg (fixed pkg id → upgrades via installer).
# Usage: package_macos_pkg.sh <app-path> <out-pkg> <version>
#
# BundleIsRelocatable is forced false so PackageKit does not upgrade a
# Flutter Debug build under ~/Documents (same CFBundleIdentifier) and fail
# with PKInstallErrorDomain 120 / Operation not permitted.
set -euo pipefail

APP="${1:-}"
OUT_PKG="${2:-}"
VER="${3:-}"
ID="com.bbdevs.helmhost"

if [[ -z "$APP" || -z "$OUT_PKG" || -z "$VER" ]]; then
  echo "usage: $0 <Helmhost.app|helmhost.app> <out.pkg> <version>" >&2
  exit 1
fi
if [[ ! -d "$APP" ]]; then
  echo "error: missing app bundle: $APP" >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/helmhost-pkg.XXXXXX")"
STAGE="$WORK/root"
COMPONENTS_PLIST="$WORK/components.plist"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$STAGE"
# Install as Helmhost.app under /Applications
ditto "$APP" "$STAGE/Helmhost.app"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
chmod +x "$ROOT/scripts/package_macos_uninstall.sh"
"$ROOT/scripts/package_macos_uninstall.sh" "$STAGE"

pkgbuild --analyze --root "$STAGE" "$COMPONENTS_PLIST"

# Disable relocation for every analyzed bundle entry.
i=0
while /usr/libexec/PlistBuddy -c "Print :$i:RootRelativeBundlePath" "$COMPONENTS_PLIST" &>/dev/null; do
  /usr/libexec/PlistBuddy -c "Set :$i:BundleIsRelocatable false" "$COMPONENTS_PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$i:BundleIsRelocatable bool false" "$COMPONENTS_PLIST"
  i=$((i + 1))
done
if [[ "$i" -eq 0 ]]; then
  echo "error: pkgbuild --analyze produced no component entries" >&2
  exit 1
fi
echo "components: set BundleIsRelocatable=false on $i bundle(s)"

pkgbuild \
  --root "$STAGE" \
  --component-plist "$COMPONENTS_PLIST" \
  --identifier "$ID" \
  --version "$VER" \
  --install-location /Applications \
  "$OUT_PKG"

echo "wrote $OUT_PKG (id=$ID version=$VER, non-relocatable, includes UninstallHelmhost.app)"
