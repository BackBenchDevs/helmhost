#!/usr/bin/env bash
# Release desktop packages for the current OS (rcs + stable).
# Produces portable zip/tar plus upgradeable installers
# (.pkg / .deb / .rpm / .AppImage / -setup.exe).
#
# Artifact names:
#   helmhost-{channel}-{os}-{arch}-{codename}-v{ver}[-rc.N][-setup].{ext}
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${ROOT}/tools/flutter/bin:${PATH:-}"
unset CARGO_TARGET_DIR
CHANNEL="${HELMHOST_CHANNEL:-stable}"
VER="$(tr -d '[:space:]' <"$ROOT/VERSION")"
OUT="$ROOT/dist/${CHANNEL}"
mkdir -p "$OUT"
chmod +x "$ROOT"/scripts/*.sh 2>/dev/null || true

basename_art() {
  # usage: basename_art <os> <arch> <ext> [--setup]
  local os="$1" arch="$2" ext="$3"
  shift 3
  "$ROOT/scripts/artifact_basename.sh" \
    --os "$os" --arch "$arch" --ext "$ext" --channel "$CHANNEL" --ver "$VER" "$@"
}

cd "$ROOT"
./scripts/hh-version sync --build "${GITHUB_RUN_NUMBER:-1}"
cargo build -p helmhost-ffi --release
cd "$ROOT/apps/client"
flutter pub get

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

zip_dir() {
  local src="$1" dest="$2"
  rm -f "$dest"
  if command -v zip >/dev/null 2>&1; then
    (cd "$src" && zip -r "$dest" .)
  elif command -v powershell.exe >/dev/null 2>&1; then
    local src_w dest_w
    src_w="$(win_path "$src")"
    dest_w="$(win_path "$dest")"
    powershell.exe -NoProfile -Command \
      "Compress-Archive -Path (Join-Path '$src_w' '*') -DestinationPath '$dest_w' -Force"
  else
    echo "error: need zip or powershell Compress-Archive" >&2
    exit 1
  fi
}

case "$(uname -s)" in
  Darwin)
    flutter build macos --release
    APP="build/macos/Build/Products/Release/helmhost.app"
    "$ROOT/scripts/copy_ffi_into_bundle.sh" release "$ROOT/apps/client/${APP}/Contents/MacOS"
    ARCH="$(uname -m)"
    ZIP="$OUT/$(basename_art macos "$ARCH" zip)"
    ditto -c -k --sequesterRsrc --keepParent \
      "$ROOT/apps/client/${APP}" "$ZIP"
    echo "wrote $ZIP"
    "$ROOT/scripts/assert_ffi_in_artifact.sh" "$ZIP"
    PKG="$OUT/$(basename_art macos "$ARCH" pkg)"
    "$ROOT/scripts/package_macos_pkg.sh" "$ROOT/apps/client/${APP}" "$PKG" "$VER"
    echo "wrote $PKG"
    ;;
  Linux)
    flutter build linux --release
    BUNDLE="build/linux/x64/release/bundle"
    "$ROOT/scripts/copy_ffi_into_bundle.sh" release "$ROOT/apps/client/${BUNDLE}"
    TAR="$OUT/$(basename_art linux x64 tar.gz)"
    tar -C "$ROOT/apps/client/${BUNDLE}" -czf "$TAR" .
    echo "wrote $TAR"
    "$ROOT/scripts/assert_ffi_in_artifact.sh" "$TAR"
    DEB="$OUT/$(basename_art linux x64 deb)"
    "$ROOT/scripts/package_linux_deb.sh" "$ROOT/apps/client/${BUNDLE}" "$DEB" "$VER" "$CHANNEL"
    echo "wrote $DEB"
    RPM="$OUT/$(basename_art linux x64 rpm)"
    "$ROOT/scripts/package_linux_rpm.sh" "$ROOT/apps/client/${BUNDLE}" "$RPM" "$VER" "$CHANNEL"
    echo "wrote $RPM"
    APPIMAGE="$OUT/$(basename_art linux x64 AppImage)"
    "$ROOT/scripts/package_linux_appimage.sh" "$ROOT/apps/client/${BUNDLE}" "$APPIMAGE" "$VER" "$CHANNEL"
    echo "wrote $APPIMAGE"
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    flutter build windows --release
    REL="build/windows/x64/runner/Release"
    "$ROOT/scripts/copy_ffi_into_bundle.sh" release "$ROOT/apps/client/${REL}"
    ZIP="$OUT/$(basename_art windows x64 zip)"
    zip_dir "$ROOT/apps/client/${REL}" "$ZIP"
    echo "wrote $ZIP"
    "$ROOT/scripts/assert_ffi_in_artifact.sh" "$ZIP"
    SETUP_NAME="$(basename_art windows x64 exe --setup)"
    "$ROOT/scripts/package_windows_inno.sh" \
      "$ROOT/apps/client/${REL}" "$OUT" "$VER" "$CHANNEL" "$SETUP_NAME"
    ;;
  *)
    echo "unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

"$ROOT/scripts/write_digests.sh" "$OUT"

echo "artifacts in $OUT:"
ls -la "$OUT"
