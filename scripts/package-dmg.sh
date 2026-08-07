#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${CONFIGURATION:-release}
version=${VERSION:-0.1.0}
bundle_identifier=${BUNDLE_IDENTIFIER:-com.eugenius.screen-shifter}
output_root=${OUTPUT_ROOT:-"$project_root/.build/package"}
app_path="$output_root/Screen Shifter.app"
dmg_path="$output_root/Screen-Shifter-$version.dmg"

cd "$project_root"
swift build -c "$configuration" --product ScreenShifter

rm -rf "$app_path" "$dmg_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp ".build/$configuration/ScreenShifter" "$app_path/Contents/MacOS/ScreenShifter"

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
printf '%s\n' '</dict></plist>' >> "$app_path/Contents/Info.plist"

if test -n "${CODESIGN_IDENTITY:-}"; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$app_path"
fi

hdiutil create \
    -volname "Screen Shifter $version" \
    -srcfolder "$app_path" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null

printf 'Created %s\n' "$dmg_path"
