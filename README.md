# Screen Shifter

Screen Shifter is a native macOS menu bar app that saves and restores display scaling profiles for known displays.

It runs locally on macOS 14 or newer, has no runtime account or service dependency, and can receive signed updates from a public GitHub release repository.

## Build

```sh
swift build
swift test
```

## Package

```sh
./scripts/package-dmg.sh
```

See [docs/packaging.md](docs/packaging.md) for signed packaging and manual release publishing.