#!/usr/bin/env bash
# scripts/release.sh — build VZenit.app and zip it for distribution.
#
# Produces a Release-configured, ad-hoc-signed .app and packages it as
# dist/VZenit-<version>.zip for sending to testers. The recipient will
# need to clear the quarantine attribute or right-click → Open the
# first time, since the build isn't notarized.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Tool checks
command -v xcodegen >/dev/null || {
  echo "ERROR: xcodegen not found. Install with: brew install xcodegen"
  exit 1
}

# Use Xcode's xcodebuild explicitly — system /usr/bin/xcodebuild may point at
# Command Line Tools, which can't build a SwiftUI macOS app target.
XCODEBUILD="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
[[ -x "$XCODEBUILD" ]] || XCODEBUILD="xcodebuild"

# Read MARKETING_VERSION from project.yml
VERSION=$(grep -E '^\s+MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
VERSION="${VERSION:-dev}"

echo "Generating Xcode project..."
xcodegen generate

BUILD_DIR="$REPO_ROOT/build"
DIST_DIR="$REPO_ROOT/dist"
mkdir -p "$DIST_DIR"

echo
echo "Building VZenit Release ($VERSION)..."
echo
"$XCODEBUILD" \
  -project VZenit.xcodeproj \
  -scheme VZenit \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$BUILD_DIR/Build/Products/Release/VZenit.app"
[[ -d "$APP_PATH" ]] || {
  echo "ERROR: VZenit.app not found at $APP_PATH"
  exit 1
}

ZIP_PATH="$DIST_DIR/VZenit-$VERSION.zip"
rm -f "$ZIP_PATH"

echo
echo "Packaging $(basename "$ZIP_PATH")..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

SIZE=$(du -h "$ZIP_PATH" | cut -f1)

cat <<MSG

Built: $ZIP_PATH ($SIZE)

Send the zip to your tester. First-launch instructions for them:

    xattr -cr ~/Downloads/VZenit.app && open ~/Downloads/VZenit.app

Or in Finder: drag to /Applications, right-click → Open, click Open
in the Gatekeeper dialog. After that it'll launch normally.

MSG
