#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$HOME/Desktop/Drishti Floating Pumpkin.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo "Building Drishti Floating Pumpkin.app..."
rm -rf "$APP"
mkdir -p "$MACOS" "$RES/assets"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Apple command line developer tools are required for the one-time build."
  echo "Run: xcode-select --install"
  read -p "Press Enter to close..."
  exit 1
fi

xcrun swiftc "$SCRIPT_DIR/DrishtiOverlay.swift" \
  -o "$MACOS/DrishtiFloatingPumpkin" \
  -framework Cocoa \
  -framework WebKit

cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/index.html" "$RES/index.html"
cp -R "$ROOT/assets/"* "$RES/assets/"

chmod +x "$MACOS/DrishtiFloatingPumpkin"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo ""
echo "Done."
echo "Created: $APP"
open -R "$APP"
read -p "Press Enter to close..."
