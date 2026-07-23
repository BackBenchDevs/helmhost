# Helmhost

Desktop-first open RFB / VNC viewer: Flutter UI + Rust protocol engine.

## Docs map

This site is the **public** docs tree. Local planning notes may live under `plan_docs/` (often gitignored).

## Channels

| Channel | How | Artifacts |
|---------|-----|-----------|
| **dev** | Push to `main` / `dev` → prerelease `dev-<sha>` | portable zip/tar |
| **rcs** | Tag `vX.Y.Z-rc.N` | zip/tar + `.pkg` / `.deb` / `-setup.exe` |
| **stable** | Tag `vX.Y.Z` via `./scripts/hh-version` | same as rcs |

Installers are upgradeable (macOS pkg `com.bbdevs.helmhost` / deb `helmhost` / fixed Inno AppId). Docs site: GitHub Pages from `docs/` (Actions).
