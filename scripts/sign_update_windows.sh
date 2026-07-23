#!/usr/bin/env bash
# Sign a Windows update binary with DSA-4096 private key (WinSparkle).
# Usage: sign_update_windows.sh <setup.exe> <dsa_priv.pem>
# Prints: <dsaSignature>
set -euo pipefail
FILE="${1:?file}"
KEY="${2:?dsa private key pem}"
# WinSparkle legacy: DSA-SHA1 signature of file bytes (openssl).
SIG="$(openssl dgst -sha1 -binary <"$FILE" | openssl dgst -sha1 -sign "$KEY" | openssl enc -base64 | tr -d '\n')"
printf '%s\n' "$SIG"
