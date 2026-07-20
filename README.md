# Helmhost

Open multi-session RFB / VNC viewer — Flutter desktop UI + Rust protocol engine (GPL-2.0-or-later).

[![CI](https://github.com/helmhost/helmhost/actions/workflows/ci.yml/badge.svg)](https://github.com/helmhost/helmhost/actions/workflows/ci.yml)

> Replace the badge org/repo path if this fork uses a different GitHub remote.

## Quick start (macOS)

```bash
./scripts/build_client.sh
cd apps/client && flutter run -d macos
```

## Version (single source of truth)

```bash
./scripts/hh-version show
./scripts/hh-version bump patch
./scripts/hh-version tag          # annotated vX.Y.Z
./scripts/hh-version tag --rc 1   # vX.Y.Z-rc.1
```

Do **not** hand-edit version in `Cargo.toml` / `pubspec.yaml`.

## Tests / CI locally

```bash
./scripts/ci_rust.sh
./scripts/ci_flutter.sh
```

## Build channels

| Channel | Script / trigger |
|---------|------------------|
| **dev** | `./scripts/build_dev.sh` or push `main`/`dev` |
| **rcs** | tag `v*-rc.*` → release workflow |
| **stable** | `./scripts/hh-version tag` → release workflow |

Artifacts land under `dist/`. Unsigned builds in CI for now.

## Docs

- Changelog: [CHANGELOG.md](./CHANGELOG.md)
- Public book: `docs/` (GitHub Pages via Actions)
- Releases: GitHub Releases

## Layout

```
apps/client/     Flutter app
crates/core|rfb|ffi/
scripts/         hh-version, ci_*, build_*
docs/            mdBook site
VERSION          SSOT version
```
