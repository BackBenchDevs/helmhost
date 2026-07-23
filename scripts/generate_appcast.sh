#!/usr/bin/env bash
# Build Sparkle/WinSparkle appcast XML for a release.
#
# Required env: CHANNEL VERSION BUILD TAG OUT
# Optional: MAC_ZIP MAC_ED_SIG WIN_SETUP WIN_DSA_SIG ASSET_BASE
set -euo pipefail

CHANNEL="${CHANNEL:-stable}"
VERSION="${VERSION:?VERSION required}"
BUILD="${BUILD:-1}"
TAG="${TAG:?TAG required}"
OUT="${OUT:?OUT required}"
ASSET_BASE="${ASSET_BASE:-https://github.com/BackBenchDevs/helmhost/releases/download/${TAG}}"
PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"

escape() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g' <<<"$1"
}

{
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Helmhost ${CHANNEL}</title>
    <language>en</language>
EOF

  if [[ -n "${MAC_ZIP:-}" && -f "${MAC_ZIP}" ]]; then
    LEN="$(wc -c <"$MAC_ZIP" | tr -d ' ')"
    NAME="$(basename "$MAC_ZIP")"
    URL="$(escape "${ASSET_BASE}/${NAME}")"
    SIG="${MAC_ED_SIG:-}"
    cat <<EOF
    <item>
      <title>Helmhost v${VERSION}</title>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure url="${URL}"
                 sparkle:edSignature="${SIG}"
                 sparkle:os="macos"
                 length="${LEN}"
                 type="application/octet-stream" />
    </item>
EOF
  fi

  if [[ -n "${WIN_SETUP:-}" && -f "${WIN_SETUP}" ]]; then
    LEN="$(wc -c <"$WIN_SETUP" | tr -d ' ')"
    NAME="$(basename "$WIN_SETUP")"
    URL="$(escape "${ASSET_BASE}/${NAME}")"
    SIG="${WIN_DSA_SIG:-}"
    cat <<EOF
    <item>
      <title>Helmhost v${VERSION}</title>
      <sparkle:version>${VERSION}+${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure url="${URL}"
                 sparkle:dsaSignature="${SIG}"
                 sparkle:os="windows"
                 length="${LEN}"
                 type="application/octet-stream" />
    </item>
EOF
  fi

  cat <<EOF
  </channel>
</rss>
EOF
} >"$OUT"

echo "wrote $OUT"
