#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_PNG="$ROOT_DIR/icon.png"
DIST_DIR="$ROOT_DIR/dist"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
APP_ICON_ICNS="$DIST_DIR/AppIcon.icns"
APP_BUNDLE="$DIST_DIR/ScreenZ.app"
ZIP_PATH="$DIST_DIR/ScreenZ.zip"

if [[ ! -f "$ICON_PNG" ]]; then
  echo "Missing icon source: $ICON_PNG" >&2
  exit 1
fi

echo "Building universal release binary..."
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "Generating AppIcon.icns from icon.png..."
rm -rf "$ICONSET_DIR" "$APP_ICON_ICNS"
mkdir -p "$ICONSET_DIR"

make_icon() {
  local size="$1"
  local filename="$2"
  sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET_DIR/$filename" >/dev/null
}

make_icon 16 "icon_16x16.png"
make_icon 32 "icon_16x16@2x.png"
make_icon 32 "icon_32x32.png"
make_icon 64 "icon_32x32@2x.png"
make_icon 128 "icon_128x128.png"
make_icon 256 "icon_128x128@2x.png"
make_icon 256 "icon_256x256.png"
make_icon 512 "icon_256x256@2x.png"
make_icon 512 "icon_512x512.png"
make_icon 1024 "icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$APP_ICON_ICNS"

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_DIR/ScreenZ" "$APP_BUNDLE/Contents/MacOS/ScreenZ"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$APP_ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Applying ad-hoc signature..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Creating ZIP archive..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Done."
echo "App bundle: $APP_BUNDLE"
echo "Archive:    $ZIP_PATH"
