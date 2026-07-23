#!/usr/bin/env bash
# Stage "Uninstall Helmhost.app" into a pkgbuild root (sibling of Helmhost.app).
# Usage: package_macos_uninstall.sh <stage-dir>
set -euo pipefail

STAGE="${1:-}"
if [[ -z "$STAGE" || ! -d "$STAGE" ]]; then
  echo "usage: $0 <pkg-stage-dir>" >&2
  exit 1
fi

APP="$STAGE/Uninstall Helmhost.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
mkdir -p "$MACOS" "$CONTENTS/Resources"

cat >"$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>uninstall</string>
  <key>CFBundleIdentifier</key>
  <string>com.bbdevs.helmhost.uninstall</string>
  <key>CFBundleName</key>
  <string>Uninstall Helmhost</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cat >"$MACOS/uninstall" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
osascript <<'APPLESCRIPT'
set keepData to true
try
  set answer to button returned of (display dialog ¬
    "Uninstall Helmhost from /Applications?" & return & return & ¬
    "Your library (~/.helmhost) is kept by default." ¬
    buttons {"Cancel", "Uninstall"} default button "Uninstall" with icon caution)
  if answer is "Cancel" then return
on error number -128
  return
end try

try
  do shell script "pkill -x helmhost || pkill -x Helmhost || true"
end try
delay 0.5

do shell script "rm -rf '/Applications/Helmhost.app'" with administrator privileges
do shell script "pkgutil --forget com.bbdevs.helmhost || true" with administrator privileges
do shell script "rm -rf '/Applications/Uninstall Helmhost.app'" with administrator privileges

display dialog "Helmhost was removed. User data in ~/.helmhost was kept." buttons {"OK"} default button "OK"
APPLESCRIPT
SCRIPT
chmod 755 "$MACOS/uninstall"

echo "staged $APP"
