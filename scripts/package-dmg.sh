#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${CONFIGURATION:-release}
version=${VERSION:-0.1.0}
bundle_identifier=${BUNDLE_IDENTIFIER:-com.eugenius.screen-shifter}
sparkle_feed_url=${SPARKLE_FEED_URL:-https://github.com/Eugenius-S/screen-shifter/releases/latest/download/appcast.xml}
sparkle_public_ed_key=${SPARKLE_PUBLIC_ED_KEY:-}
output_root=${OUTPUT_ROOT:-"$project_root/.build/package"}
app_path="$output_root/Screen Shifter.app"
dmg_path="$output_root/Screen-Shifter-$version.dmg"

cd "$project_root"
swift build -c "$configuration" --product ScreenShifter

rm -rf "$app_path" "$dmg_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp ".build/$configuration/ScreenShifter" "$app_path/Contents/MacOS/ScreenShifter"

sparkle_framework=$(find .build -type d -path "*/$configuration/Sparkle.framework" -print -quit)
if test -z "$sparkle_framework"; then
    printf 'Sparkle.framework was not found after swift build\n' >&2
    exit 1
fi

mkdir -p "$app_path/Contents/Frameworks"
cp -R "$sparkle_framework" "$app_path/Contents/Frameworks/"
install_name_tool -add_rpath '@loader_path/../Frameworks' "$app_path/Contents/MacOS/ScreenShifter"

if test -n "${CODESIGN_IDENTITY:-}" && test -z "$sparkle_public_ed_key"; then
    printf 'SPARKLE_PUBLIC_ED_KEY is required for signed packaging\n' >&2
    exit 1
fi

printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' > "$app_path/Contents/Info.plist"
printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "$app_path/Contents/Info.plist"
printf '%s\n' '<plist version="1.0"><dict>' >> "$app_path/Contents/Info.plist"
printf '%s\n' "<key>CFBundleDisplayName</key><string>Screen Shifter</string>" >> "$app_path/Contents/Info.plist"
printf '%s\n' "<key>CFBundleExecutable</key><string>ScreenShifter</string>" >> "$app_path/Contents/Info.plist"
printf '%s\n' "<key>CFBundleIdentifier</key><string>$bundle_identifier</string>" >> "$app_path/Contents/Info.plist"
printf '%s\n' "<key>CFBundleName</key><string>Screen Shifter</string>" >> "$app_path/Contents/Info.plist"
printf '%s\n' "<key>CFBundlePackageType</key><string>APPL</string>" >> "$app_path/Contents/Info.plist"
printf '%s\n' "<key>CFBundleShortVersionString</key><string>$version</string>" >> "$app_path/Contents/Info.plist"
printf '%s\n' "<key>CFBundleVersion</key><string>$version</string>" >> "$app_path/Contents/Info.plist"
printf '%s\n' '<key>LSMinimumSystemVersion</key><string>14.0</string>' >> "$app_path/Contents/Info.plist"
printf '%s\n' '<key>LSUIElement</key><true/>' >> "$app_path/Contents/Info.plist"
printf '%s\n' '<key>NSHighResolutionCapable</key><true/>' >> "$app_path/Contents/Info.plist"
printf '%s\n' "<key>SUFeedURL</key><string>$sparkle_feed_url</string>" >> "$app_path/Contents/Info.plist"
printf '%s\n' '<key>SUEnableAutomaticChecks</key><true/>' >> "$app_path/Contents/Info.plist"
printf '%s\n' '<key>SUAutomaticallyUpdate</key><true/>' >> "$app_path/Contents/Info.plist"
printf '%s\n' '<key>SUAllowsAutomaticUpdates</key><true/>' >> "$app_path/Contents/Info.plist"
printf '%s\n' '<key>SUScheduledCheckInterval</key><integer>86400</integer>' >> "$app_path/Contents/Info.plist"
if test -n "$sparkle_public_ed_key"; then
    printf '%s\n' "<key>SUPublicEDKey</key><string>$sparkle_public_ed_key</string>" >> "$app_path/Contents/Info.plist"
    printf '%s\n' '<key>SUVerifyUpdateBeforeExtraction</key><true/>' >> "$app_path/Contents/Info.plist"
    printf '%s\n' '<key>SURequireSignedFeed</key><true/>' >> "$app_path/Contents/Info.plist"
fi
printf '%s\n' '</dict></plist>' >> "$app_path/Contents/Info.plist"

if test -n "${CODESIGN_IDENTITY:-}"; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" \
        "$app_path/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" \
        "$app_path/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" \
        "$app_path/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" \
        "$app_path/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" \
        "$app_path/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$app_path"
fi

hdiutil create \
    -volname "Screen Shifter $version" \
    -srcfolder "$app_path" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null

printf 'Created %s\n' "$dmg_path"
