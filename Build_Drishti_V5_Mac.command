#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Desktop/Drishti V5.1.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo ""
echo "========================================"
echo "  Building Drishti V5.1 — Native Physics"
echo "========================================"
echo ""

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Apple Command Line Tools are required for this one-time build."
  echo "macOS should offer to install them if you run:"
  echo "  xcode-select --install"
  echo ""
  read -p "Press Enter to close..."
  exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

echo "Compiling native SpriteKit app..."
xcrun swiftc \
  "$SCRIPT_DIR/Source/DrishtiV5.swift" \
  -o "$MACOS/DrishtiV5" \
  -framework Cocoa \
  -framework SpriteKit \
  -framework AVFoundation

echo "Copying realistic assets..."
cp "$SCRIPT_DIR/Resources/pumpkin_camphor.png" "$RES/"
cp "$SCRIPT_DIR/Resources/impact_crack.wav" "$RES/"
cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"

echo "Creating app icon..."
ICONSET="$SCRIPT_DIR/.AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16     "$SCRIPT_DIR/Resources/AppIcon1024.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$SCRIPT_DIR/Resources/AppIcon1024.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$SCRIPT_DIR/Resources/AppIcon1024.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$SCRIPT_DIR/Resources/AppIcon1024.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$SCRIPT_DIR/Resources/AppIcon1024.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$SCRIPT_DIR/Resources/AppIcon1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$SCRIPT_DIR/Resources/AppIcon1024.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$SCRIPT_DIR/Resources/AppIcon1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$SCRIPT_DIR/Resources/AppIcon1024.png" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$SCRIPT_DIR/Resources/AppIcon1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
rm -rf "$ICONSET"

chmod +x "$MACOS/DrishtiV5"

echo "Ad-hoc signing..."
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo ""
echo "Build complete."
echo ""
echo "Created:"
echo "  $APP"
echo ""
echo "From now on, simply double-click Drishti V5.1.app."
echo "No Xcode window needs to be open."
echo ""
open -R "$APP"
read -p "Press Enter to close..."
