#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$REPO_ROOT/Build}"
ARCH="${ARCH:-$(uname -m)}"
cd "$REPO_ROOT"
swift build -c release --arch "$ARCH"
BIN_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/goldprice-bundle.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/GoldPrice.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUTPUT_DIR"
cp -X "$BIN_DIR/GoldPrice" "$APP/Contents/MacOS/GoldPrice"
cp -X Info.plist "$APP/Contents/Info.plist"
cp -X Assets/AppIcon.icns "$APP/Contents/Resources/GoldPrice.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
ZIP="$OUTPUT_DIR/GoldPrice-$VERSION-macOS-$ARCH.zip"
ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
ditto --norsrc "$APP" "$OUTPUT_DIR/GoldPrice.app"
printf 'App: %s\nZIP: %s\n' "$OUTPUT_DIR/GoldPrice.app" "$ZIP"
