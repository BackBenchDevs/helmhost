#!/usr/bin/env bash
# Assert a portable archive contains the native FFI library.
# Usage: assert_ffi_in_artifact.sh <zip|tar.gz path>
set -euo pipefail

ART="${1:-}"
if [[ -z "$ART" || ! -f "$ART" ]]; then
  echo "usage: $0 <artifact.zip|.tar.gz>" >&2
  exit 1
fi

case "$ART" in
  *.zip)
    LIST="$(unzip -l "$ART" 2>/dev/null || zipinfo -1 "$ART")"
    ;;
  *.tar.gz|*.tgz)
    LIST="$(tar -tzf "$ART")"
    ;;
  *)
    echo "error: unsupported artifact type: $ART" >&2
    exit 1
    ;;
esac

if echo "$LIST" | grep -E 'helmhost_ffi\.(dll|dylib|so)|libhelmhost_ffi\.(dylib|so)' >/dev/null; then
  echo "ok: FFI present in $ART"
  exit 0
fi

echo "error: helmhost_ffi missing from $ART" >&2
echo "$LIST" | head -40 >&2
exit 1
