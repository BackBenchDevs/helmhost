# Versioning

Edit version **only** through the CLI:

```bash
./scripts/hh-version show
./scripts/hh-version bump patch
./scripts/hh-version tag              # vX.Y.Z
./scripts/hh-version tag --rc 1       # vX.Y.Z-rc.1
./scripts/hh-version check-tag v0.1.0 # CI: tag must match VERSION
```

`VERSION` is the single source of truth. Cargo + Flutter `pubspec` are mirrors.

Release workflow runs `check-tag` before build: stable `vX.Y.Z` and RC `vX.Y.Z-rc.N` both require `VERSION == X.Y.Z`.
