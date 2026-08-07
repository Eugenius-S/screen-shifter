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

Sparkle is embedded in `Contents/Frameworks`. The package script uses this default appcast URL:

```text
https://github.com/Eugenius-S/screen-shifter/releases/latest/download/appcast.xml
```

For signed packaging, provide the Sparkle Ed25519 public key through `SPARKLE_PUBLIC_ED_KEY`. The matching private key stays in the release machine's Keychain and is used by Sparkle's `generate_appcast` tool. Signed packaging fails when `CODESIGN_IDENTITY` is set without the public key.
