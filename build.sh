#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_NAME="Claude Usage Bar"
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

echo "Generating .icns icon..."
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
sips -z 16 16     claude-bar-app-icon.png --out "$ICONSET/icon_16x16.png"      > /dev/null
sips -z 32 32     claude-bar-app-icon.png --out "$ICONSET/icon_16x16@2x.png"   > /dev/null
sips -z 32 32     claude-bar-app-icon.png --out "$ICONSET/icon_32x32.png"      > /dev/null
sips -z 64 64     claude-bar-app-icon.png --out "$ICONSET/icon_32x32@2x.png"   > /dev/null
sips -z 128 128   claude-bar-app-icon.png --out "$ICONSET/icon_128x128.png"    > /dev/null
sips -z 256 256   claude-bar-app-icon.png --out "$ICONSET/icon_128x128@2x.png" > /dev/null
sips -z 256 256   claude-bar-app-icon.png --out "$ICONSET/icon_256x256.png"    > /dev/null
sips -z 512 512   claude-bar-app-icon.png --out "$ICONSET/icon_256x256@2x.png" > /dev/null
sips -z 512 512   claude-bar-app-icon.png --out "$ICONSET/icon_512x512.png"    > /dev/null
sips -z 1024 1024 claude-bar-app-icon.png --out "$ICONSET/icon_512x512@2x.png" > /dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

mv "$BINARY" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

# Sign with a real code-signing identity if one exists, so the macOS Keychain
# "Always Allow" grant persists across launches and rebuilds. Ad-hoc / linker
# signatures get a per-build cdhash identity that the Keychain won't remember, so
# Claude Code's token prompt would otherwise reappear on every launch. Override the
# identity with CODESIGN_IDENTITY=...; on CI (no identity in the keychain) this is
# skipped and the released bundle stays ad-hoc, exactly as before.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' 'NR==1{print $2}')}"
if [[ -n "$CODESIGN_IDENTITY" ]]; then
    echo "Signing with '$CODESIGN_IDENTITY'..."
    codesign --force --sign "$CODESIGN_IDENTITY" "$APP"
else
    echo "No code-signing identity found; leaving ad-hoc (Keychain prompt will recur)."
fi

echo "Done: $APP"

if [[ "$1" == "--install" ]]; then
    INSTALLED="/Applications/$APP_NAME.app"
    echo ""
    echo "Installing to $INSTALLED..."
    pkill -x "$BINARY" 2>/dev/null || true
    rm -rf "$INSTALLED"
    cp -R "$APP" "/Applications/"
    open "$INSTALLED"
    echo "Installed and launched."
else
    echo ""
    echo "Run with:        open \"$APP\""
    echo "Install + run:   ./build.sh --install"
fi
