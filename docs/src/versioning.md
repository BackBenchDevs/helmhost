# Versioning

Edit version **only** through the CLI:

```bash
./scripts/hh-version show
./scripts/hh-version bump patch
./scripts/hh-version tag              # vX.Y.Z
./scripts/hh-version tag --rc 1       # vX.Y.Z-rc.1
```

`VERSION` is the single source of truth. Cargo + Flutter `pubspec` are mirrors.
