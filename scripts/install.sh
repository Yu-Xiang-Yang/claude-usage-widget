#!/bin/bash
# Installs the latest release of Claude Usage Widget on macOS 14 or later.
#
#   bash scripts/install.sh
#   curl -fsSL https://raw.githubusercontent.com/Yu-Xiang-Yang/claude-usage-widget/main/scripts/install.sh | bash
#
# Steps: download the checksum list and the release archive, verify the checksum and the code signature,
# quit a running copy, replace /Applications/ClaudeUsageWidget.app and open it.
# Environment: INSTALL_DIR (default /Applications), NO_LAUNCH=1 (do not open the app).
#
# Files fetched with curl carry no quarantine flag, so macOS does not block the first launch the way it
# blocks a browser download of this unnotarized app.
set -euo pipefail

REPO="Yu-Xiang-Yang/claude-usage-widget"
BASE="https://github.com/$REPO/releases/latest/download"
DEST="${INSTALL_DIR:-/Applications}"
APP="ClaudeUsageWidget.app"

fail() { echo "error: $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "this widget runs on macOS only"
version="$(sw_vers -productVersion)"
[ "${version%%.*}" -ge 14 ] || fail "macOS 14 or later is required (found $version)"
mkdir -p "$DEST" 2>/dev/null || true
[ -w "$DEST" ] || fail "cannot write to $DEST; set INSTALL_DIR to a writable folder, for example \$HOME/Applications"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Fetching the checksum list of the latest release..."
curl -fsSL "$BASE/SHA256SUMS.txt" -o "$work/SHA256SUMS.txt"
archive="$(awk '{print $2}' "$work/SHA256SUMS.txt" | grep -E '^ClaudeUsageWidget-.*-macos\.zip$' | head -1 || true)"
[ -n "$archive" ] || fail "the release does not list a ClaudeUsageWidget archive"

echo "Downloading $archive..."
curl -fsSL "$BASE/$archive" -o "$work/$archive"

echo "Verifying the checksum..."
(cd "$work" && shasum -a 256 -c SHA256SUMS.txt)

ditto -x -k "$work/$archive" "$work/extracted"
codesign --verify --deep --strict "$work/extracted/$APP" || fail "the code signature of the download is not valid"

# A running copy is quit so that it can be replaced; its settings and sign-in are kept.
pkill -f "$DEST/$APP/Contents/MacOS/ClaudeUsageWidget" 2>/dev/null || true
sleep 1
rm -rf "$DEST/$APP"
ditto "$work/extracted/$APP" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

installed="$(plutil -extract CFBundleShortVersionString raw "$DEST/$APP/Contents/Info.plist")"
echo "Installed Claude Usage Widget $installed to $DEST/$APP"

if [ "${NO_LAUNCH:-0}" != "1" ]; then
    open "$DEST/$APP"
fi

cat <<NEXT

Next steps:
  1. Right-click the widget and choose "Sign In to claude.ai..." to show the 5-hour and weekly limits.
     You sign in yourself in the window that opens; the widget never sees your password.
  2. Optional: right-click, then "Launch at Login" (or run: "$DEST/$APP/Contents/MacOS/ClaudeUsageWidget" --login-item on).
NEXT
