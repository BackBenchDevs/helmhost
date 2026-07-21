# Helmhost

Open multi-session RFB / VNC viewer — Flutter desktop UI + Rust protocol engine (GPL-2.0-or-later).

[![CI](https://github.com/BackBenchDevs/helmhost/actions/workflows/ci.yml/badge.svg)](https://github.com/BackBenchDevs/helmhost/actions/workflows/ci.yml)

## Quick start (macOS)

```bash
./scripts/build_client.sh
```

## Version (single source of truth)

Era **Lighthouse** · current line **Lantern** (`0.1.0`). Map: [`codenames.toml`](./codenames.toml).

```bash
./scripts/hh-version show              # Helmhost - Lantern (v0.1.0 - <sha>) - …
./scripts/hh-version show -a           # + release / era / semver fields
./scripts/hh-version show --json
./scripts/hh-version bump patch
./scripts/hh-version tag               # annotated vX.Y.Z
./scripts/hh-version tag --rc 1        # vX.Y.Z-rc.1
```

Do **not** hand-edit version in `Cargo.toml` / `pubspec.yaml`. Details: [docs/src/versioning.md](./docs/src/versioning.md).

## Build packages (native OS only — no cross-compile)

```bash
./scripts/hh-version sync
./scripts/build_release.sh    # → dist/<channel>/
```

| Host | Portable | Installable (upgradeable) |
|------|----------|---------------------------|
| macOS | `.zip` (`.app`) | `.pkg` (`dev.helmhost.client`) |
| Linux | `.tar.gz` | `.deb` (package `helmhost`) |
| Windows | `.zip` | `-setup.exe` (Inno, fixed AppId) |

Windows local: install [Inno Setup 6](https://jrsoftware.org/isinfo.php) so `ISCC.exe` is on PATH.  
Dev/debug portable only: `./scripts/build_dev.sh`.

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

Artifacts land under `dist/` and on GitHub Releases. Unsigned in CI for now.

## GitHub ops checklist (first publish)

Repo: **[BackBenchDevs/helmhost](https://github.com/BackBenchDevs/helmhost)** (`origin` → github.com, not Broadcom).

1. Commit local work, then: `git push -u origin master` (or `main`)
2. **Pages:** Settings → Pages → Source **GitHub Actions**
3. After docs deploy: `https://backbenchdevs.github.io/helmhost/`
4. First Lantern release:
   ```bash
   ./scripts/hh-version tag
   git push origin v0.1.0
   ```
   Release assets include packages + **SHA256SUMS** / `*.sha256` digests.

## Docs

- Changelog: [CHANGELOG.md](./CHANGELOG.md)
- Public book: `docs/` (GitHub Pages via Actions)
- Releases: GitHub Releases

## Layout

```
apps/client/     Flutter app
crates/core|rfb|ffi/
packaging/       Windows Inno (.iss)
scripts/         hh-version, build_*, package_*, ci_*
docs/            mdBook site
VERSION          SSOT version
codenames.toml   era / codename milestone map
```
