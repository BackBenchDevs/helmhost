# Helmhost

Desktop-first open RFB / VNC viewer: Flutter UI + Rust protocol engine.

## Docs map

This site is the **public** docs tree. Local planning notes may live under `plan_docs/` (often gitignored).

## Channels

| Channel | How | Artifacts |
|---------|-----|-----------|
| **dev** | Push to `main` / `dev` → prerelease `dev-<sha>` | portable zip/tar (`helmhost-dev-…-{sha}.{ext}`) |
| **rcs** | Tag `vX.Y.Z-rc.N` | zip/tar/AppImage + `.pkg` / `.deb` / `.rpm` / `-setup.exe` |
| **stable** | Tag `vX.Y.Z` via `./scripts/hh-version` | same as rcs |

Name pattern: `helmhost-{channel}-{os}-{arch}-{codename}-v{ver}[-rc.N][-setup].{ext}`
(e.g. `helmhost-stable-linux-x64-lantern-v0.1.0.deb`).

Installers are upgradeable (macOS pkg `com.bbdevs.helmhost` / deb+rpm `helmhost` / fixed Inno AppId). Docs site: GitHub Pages from `docs/` (Actions).
