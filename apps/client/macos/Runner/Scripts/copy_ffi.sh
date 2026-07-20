#!/bin/sh
# Copy helmhost-ffi into the app bundle (Contents/MacOS).
# SRCROOT = apps/client/macos
set -e
REPO_ROOT="$(cd "${SRCROOT}/../../.." && pwd)"
PROFILE=debug
case "${CONFIGURATION}" in
  Release|Profile) PROFILE=release ;;
esac
LIB="${REPO_ROOT}/target/${PROFILE}/libhelmhost_ffi.dylib"
if [ ! -f "$LIB" ]; then
  LIB="${REPO_ROOT}/target/debug/libhelmhost_ffi.dylib"
fi
if [ ! -f "$LIB" ] && [ -n "${CARGO_TARGET_DIR:-}" ]; then
  LIB="${CARGO_TARGET_DIR}/${PROFILE}/libhelmhost_ffi.dylib"
  if [ ! -f "$LIB" ]; then
    LIB="${CARGO_TARGET_DIR}/debug/libhelmhost_ffi.dylib"
  fi
fi
if [ ! -f "$LIB" ]; then
  echo "error: missing libhelmhost_ffi.dylib — run: cargo build -p helmhost-ffi (from ${REPO_ROOT})" >&2
  ls -la "${REPO_ROOT}/target/debug/" 2>&1 | head -20 >&2 || true
  exit 1
fi
DEST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/MacOS"
mkdir -p "${DEST}"
cp -f "${LIB}" "${DEST}/libhelmhost_ffi.dylib"
echo "Embedded ${LIB} → ${DEST}/libhelmhost_ffi.dylib"
