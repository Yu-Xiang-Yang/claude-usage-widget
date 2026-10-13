#!/bin/bash
# Builds ClaudeUsageWidget.app into ./build (requires the Xcode Command Line Tools).
# Usage: ./build.sh            build only (ARCHS="arm64 x86_64" for a universal binary, VERSION=1.2.3)
#        ./build.sh install    build and copy the app to /Applications (or ~/Applications)
set -euo pipefail

cd "$(dirname "$0")"
APP="build/ClaudeUsageWidget.app"

# The default SDK of the Command Line Tools can be newer than the installed compiler;
# prefer the macOS 26 SDK when present and fall back to the default otherwise.
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
[ -d "$SDK" ] || SDK="$(xcrun --show-sdk-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# ARCHS selects the architectures ("arm64 x86_64" builds a universal binary); VERSION sets the bundle version.
ARCHS="${ARCHS:-$(uname -m)}"
VERSION="${VERSION:-1.0.0}"
SLICES=()
for arch in $ARCHS; do
    swiftc -O -swift-version 5 \
        -sdk "$SDK" \
        -target "$arch-apple-macos14.0" \
        Sources/*.swift \
        -o "$APP/Contents/MacOS/ClaudeUsageWidget-$arch"
    SLICES+=("$APP/Contents/MacOS/ClaudeUsageWidget-$arch")
done
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/ClaudeUsageWidget"
rm -f "${SLICES[@]}"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.claude-usage-widget</string>
    <key>CFBundleName</key><string>ClaudeUsageWidget</string>
    <key>CFBundleDisplayName</key><string>Claude Usage</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
    <key>CFBundleExecutable</key><string>ClaudeUsageWidget</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# The display name follows the system language.
for entry in "en:Claude Usage" "zh-Hans:Claude 用量"; do
    lang="${entry%%:*}"; name="${entry#*:}"
    mkdir -p "$APP/Contents/Resources/$lang.lproj"
    printf '"CFBundleDisplayName" = "%s";\n"CFBundleName" = "%s";\n' "$name" "$name" \
        > "$APP/Contents/Resources/$lang.lproj/InfoPlist.strings"
done

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
    # /Applications when the user may write there (administrators), otherwise ~/Applications.
    if [ -w /Applications ]; then DEST="/Applications"; else DEST="$HOME/Applications"; fi
    mkdir -p "$DEST"
    pkill -f "$DEST/ClaudeUsageWidget.app/Contents/MacOS/ClaudeUsageWidget" 2>/dev/null || true
    rm -rf "$DEST/ClaudeUsageWidget.app"
    cp -R "$APP" "$DEST/"
    codesign --verify --deep --strict "$DEST/ClaudeUsageWidget.app" && echo "Signature verified"
    echo "Installed to $DEST/ClaudeUsageWidget.app"
fi
