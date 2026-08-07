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

Packaged builds check for updates automatically once per day and allow Sparkle to download and install signed updates in the background. The update repository and its releases must be public. The client then uses public HTTPS GitHub URLs and does not require a GitHub login, OAuth token, or API authorization.

For signed packaging, provide the Sparkle Ed25519 public key through `SPARKLE_PUBLIC_ED_KEY`. The matching private key stays outside the repository and is used by Sparkle's `generate_appcast` tool. Signed packaging fails when `CODESIGN_IDENTITY` is set without the public key.

## GitHub Releases

Releases are published manually from the maintainer's Mac with `scripts/publish-release.sh`. GitHub Actions are intentionally not used.

The source or release repository must be public for unauthenticated Sparkle downloads. The current repository is private, so either make it public or set `RELEASE_REPOSITORY` to a separate public repository that hosts the DMG and appcast.

Generate the key pair with Sparkle's `generate_keys` tool on a trusted Mac. Export the private key with `generate_keys -x` and keep it outside the repository. The public key can be used in `SPARKLE_PUBLIC_ED_KEY` because it cannot sign updates.

Create a release locally by pushing a semantic version tag:

```sh
SPARKLE_PRIVATE_ED_KEY='...' \
SPARKLE_PUBLIC_ED_KEY='...' \
VERSION=0.2.0 \
./scripts/publish-release.sh
```

The script uses your existing local `gh` authentication only for uploading the release. Users downloading updates never authenticate with GitHub.
