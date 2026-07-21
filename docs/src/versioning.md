# Versioning

Helmhost follows the same layers as Waypoint: **MAJOR → era**, **MINOR → track + codename**, **PATCH → ship inside that name**.

| Field | Current |
|-------|---------|
| Semver (SSOT) | `VERSION` → **0.1.0** |
| Era (major 0) | **Lighthouse** |
| Codename | **Lantern** (`lantern`) |
| Public | `Helmhost Lighthouse — Lantern (v0.1.0)` |
| Map | [`codenames.toml`](../../codenames.toml) |

## Bump rules

| Part | Maps to | Bump when |
|------|---------|-----------|
| MAJOR | Era | Leaving Lighthouse (e.g. 1.0.0) |
| MINOR | One track + one codename | Starting next track (new name) |
| PATCH | Ship inside same track | Bugfix / small ship — **same** codename |
| PRERELEASE | `-dev.N` \| `-rc.N` | Dogfood / candidates |

Prerelease ladder: `X.Y.Z-dev.1` → `…` → `X.Y.Z-rc.1` → `…` → `X.Y.Z` (tag `vX.Y.Z`).

## Milestone map (0.x)

| Minor | Track | Codename | Theme |
|-------|-------|----------|-------|
| 0.1.x | foundation | **Lantern** | First remote desktop light |
| 0.2.x | Lighthouse 1 | **Range** | Hub multi-session channel |
| 0.3.x | Lighthouse 2 | **Sector** | Grab / InputFocus |
| 0.4.x | Lighthouse 3 | **Beacon** | SSH / tunnel approach |
| 0.5.x | Lighthouse 4 | **Buoy** | Saved host library |

## CLI

Edit version **only** through the CLI:

```bash
./scripts/hh-version show              # short product line
./scripts/hh-version show -a           # short + labeled fields
./scripts/hh-version show --json       # machine JSON
./scripts/hh-version bump patch
./scripts/hh-version tag               # vX.Y.Z
./scripts/hh-version tag --rc 1        # vX.Y.Z-rc.1
./scripts/hh-version check-tag v0.1.0  # CI: tag must match VERSION
```

`VERSION` is the single source of truth. Cargo + Flutter `pubspec` are mirrors.
`codenames.toml` binds semver ranges to era/codename (baked into `show`).

Release workflow runs `check-tag` before build: stable `vX.Y.Z` and RC `vX.Y.Z-rc.N` both require `VERSION == X.Y.Z`.

### Short line (default)

```text
Helmhost - Lantern (v0.1.0 - a1b2c3d) - Tuesday, 21 Jul 2026, 05:37 PM +0530
```

### Marketing

```text
Helmhost Lighthouse — Lantern (v0.1.0)
```

Protocol / clap-style surfaces use **semver only** (no `+build`, no quotes).
