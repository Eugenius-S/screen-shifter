# Packaging

Build a direct-install DMG on macOS with:

```sh
./scripts/package-dmg.sh
```

The script builds the release SwiftPM product, creates `Screen Shifter.app`, sets the menu-bar-only `LSUIElement` flag, and writes the DMG under `.build/package/`.

For a signed build, provide a Developer ID Application identity:

```sh
CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
VERSION=0.1.0 \
./scripts/package-dmg.sh
```

The resulting app must be notarized and stapled before distribution. Notarization credentials and team identifiers are intentionally supplied by the release environment, not stored in this repository.