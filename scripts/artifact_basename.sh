#!/usr/bin/env bash
# Build a Helmhost release/dev artifact basename (no directory).
#
# Release pattern:
#   helmhost-{channel}-{os}-{arch}-{codename}-v{ver}[-rc.N][-setup].{ext}
# Dev pattern (--sha):
#   helmhost-dev-{os}-{arch}-{codename}-{sha}.{ext}
#
# Usage:
#   artifact_basename.sh --os linux --arch x64 --ext deb
#   artifact_basename.sh --os windows --arch x64 --ext exe --setup
#   artifact_basename.sh --os linux --arch x64 --ext tar.gz --sha abc1234
#
# Env (optional overrides):
#   HELMHOST_CHANNEL   default stable (or dev when --sha)
#   HELMHOST_RC        e.g. 8 → append -rc.8 (ignored for --sha)
#   VERSION file       used when --ver omitted
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

OS=""
ARCH=""
EXT=""
SETUP=0
CHANNEL="${HELMHOST_CHANNEL:-}"
VER=""
RC="${HELMHOST_RC:-}"
CODENAME=""
SHA=""

usage() {
  echo "usage: $0 --os OS --arch ARCH --ext EXT [--setup] [--channel C] [--ver V] [--rc N] [--codename TAG] [--sha SHA]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --os) OS="${2:-}"; shift 2 ;;
    --arch) ARCH="${2:-}"; shift 2 ;;
    --ext) EXT="${2:-}"; shift 2 ;;
    --setup) SETUP=1; shift ;;
    --channel) CHANNEL="${2:-}"; shift 2 ;;
    --ver) VER="${2:-}"; shift 2 ;;
    --rc) RC="${2:-}"; shift 2 ;;
    --codename) CODENAME="${2:-}"; shift 2 ;;
    --sha) SHA="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "error: unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$OS" && -n "$ARCH" && -n "$EXT" ]] || usage

normalize_arch() {
  case "$1" in
    x86_64|amd64|AMD64) echo x64 ;;
    aarch64|arm64|ARM64) echo arm64 ;;
    *) echo "$1" ;;
  esac
}

# Derive RC from GITHUB_REF_NAME when unset (v0.1.0-rc.8 → 8)
if [[ -z "$RC" && -n "${GITHUB_REF_NAME:-}" ]]; then
  if [[ "${GITHUB_REF_NAME}" =~ -rc\.([0-9]+)$ ]]; then
    RC="${BASH_REMATCH[1]}"
  fi
fi

if [[ -z "$CHANNEL" ]]; then
  if [[ -n "$SHA" ]]; then
    CHANNEL=dev
  elif [[ -n "$RC" ]]; then
    CHANNEL=rcs
  else
    CHANNEL=stable
  fi
fi

ARCH="$(normalize_arch "$ARCH")"

if [[ -z "$VER" ]]; then
  VER="$(tr -d '[:space:]' <"$ROOT/VERSION")"
fi

# Resolve release_tag (codename slug) from codenames.toml via hh-version json
if [[ -z "$CODENAME" ]]; then
  CODENAME="$(
    "$ROOT/scripts/hh-version" show --json 2>/dev/null \
      | sed -n 's/.*"release_tag":[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -1
  )"
  if [[ -z "$CODENAME" ]]; then
    # Fallback: parse release_tag for matching milestone (first tag in file for 0.1.x)
    CODENAME="$(
      grep -E '^release_tag[[:space:]]*=' "$ROOT/codenames.toml" | head -1 \
        | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/'
    )"
  fi
fi
CODENAME="$(printf '%s' "$CODENAME" | tr '[:upper:]' '[:lower:]')"
[[ -n "$CODENAME" ]] || { echo "error: could not resolve codename/release_tag" >&2; exit 1; }

EXT="${EXT#.}"
NAME="helmhost-${CHANNEL}-${OS}-${ARCH}-${CODENAME}"

if [[ -n "$SHA" ]]; then
  printf '%s-%s.%s\n' "$NAME" "$SHA" "$EXT"
  exit 0
fi

NAME="${NAME}-v${VER}"
if [[ -n "$RC" ]]; then
  NAME="${NAME}-rc.${RC}"
fi
if [[ "$SETUP" -eq 1 ]]; then
  NAME="${NAME}-setup"
fi
printf '%s.%s\n' "$NAME" "$EXT"
