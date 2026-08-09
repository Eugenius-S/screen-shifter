#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=${VERSION:-}
release_repository=${RELEASE_REPOSITORY:-Eugenius-S/screen-shifter}
public_key=${SPARKLE_PUBLIC_ED_KEY:-}
private_key=${SPARKLE_PRIVATE_ED_KEY:-}
feed_url=${SPARKLE_FEED_URL:-https://github.com/$release_repository/releases/latest/download/appcast.xml}
codesign_identity=${CODESIGN_IDENTITY:--}
release_dir="$project_root/.build/release/$version"

case "$version" in
    ''|*[!0-9.]*|.*|*.)
        printf 'VERSION must contain only numbers and dots, for example 0.2.0\n' >&2
        exit 1
        ;;
esac

if test -z "$public_key" || test -z "$private_key"; then
    printf 'SPARKLE_PUBLIC_ED_KEY and SPARKLE_PRIVATE_ED_KEY are required\n' >&2
    exit 1
fi

if test "$codesign_identity" = "-"; then
    printf 'CODESIGN_IDENTITY is not set; using ad-hoc signing for this personal release\n' >&2
fi

for command_name in gh swift; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf '%s is required\n' "$command_name" >&2
        exit 1
    fi
done

cd "$project_root"
if ! git diff --quiet || ! git diff --cached --quiet; then
    printf 'Working tree must be clean before publishing a release\n' >&2
    exit 1
fi

gh auth status >/dev/null
gh api "repos/$release_repository" --jq '.visibility' | grep -qx public || {
    printf 'Release repository must be public for unauthenticated downloads: %s\n' "$release_repository" >&2
    exit 1
}

rm -rf "$release_dir"
mkdir -p "$release_dir"

VERSION="$version" \
SPARKLE_FEED_URL="$feed_url" \
SPARKLE_PUBLIC_ED_KEY="$public_key" \
CODESIGN_IDENTITY="$codesign_identity" \
OUTPUT_ROOT="$release_dir" \
./scripts/package-dmg.sh

generate_appcast=$(find .build/artifacts/sparkle/Sparkle/bin \
    -type f -name generate_appcast -perm -111 -print -quit)
if test -z "$generate_appcast"; then
    printf 'Sparkle generate_appcast was not found; run swift build first\n' >&2
    exit 1
fi

printf '%s' "$private_key" | \
    "$generate_appcast" \
        --ed-key-file - \
        --download-url-prefix "https://github.com/$release_repository/releases/download/v$version/" \
        "$release_dir"

test -f "$release_dir/appcast.xml"
gh release create "v$version" \
    --repo "$release_repository" \
    --title "Screen Shifter $version" \
    --generate-notes \
    "$release_dir/Screen-Shifter-$version.dmg" \
    "$release_dir/appcast.xml"

printf 'Published Screen Shifter %s to %s\n' "$version" "$release_repository"
