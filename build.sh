#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_NAME="Claude Usage"
BINARY="ClaudeUsage"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "Compiling Swift..."
swiftc \
    -O \
    -framework AppKit \
    -framework Security \
    -swift-version 5 \
    -o "$BINARY" \
    Sources/*.swift

echo "Creating app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

mv "$BINARY" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/icon.png "$APP/Contents/Resources/"

echo "Done: $APP"
echo ""
echo "Run with:  open \"$APP\""
echo "Or:        \"$APP/Contents/MacOS/ClaudeUsage\""
