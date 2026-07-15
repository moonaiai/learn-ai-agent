#!/usr/bin/env bash
# Build 随心记 native into a .app bundle and install to /Applications.
# Usage: ./build.sh [--release]
set -euo pipefail

cd "$(dirname "$0")"

WEB_DIR="Sources/Suixinji/WebEditor"
if [[ ! -x "$WEB_DIR/node_modules/esbuild/bin/esbuild" || ! -d "$WEB_DIR/node_modules/prosemirror-view" ]]; then
  echo "==> npm install (WebEditor)"
  npm install --prefix "$WEB_DIR" --include=optional --include=dev
fi
echo "==> npm run build (WebEditor)"
npm run build --prefix "$WEB_DIR"

CONFIG="debug"
if [[ "${1:-}" == "--release" || "${1:-}" == "-c release" ]]; then
  CONFIG="release"
fi

APP_NAME="随心记"
BUNDLE_ID="com.suixinji.app"
BUILD_DIR=".build"
OUT_DIR="dist"
APP_BUNDLE="$OUT_DIR/${APP_NAME}.app"

echo "==> swift build -c $CONFIG"
if [[ "$CONFIG" == "release" ]]; then
  swift build -c release
  BIN="$BUILD_DIR/release/Suixinji"
else
  swift build
  BIN="$BUILD_DIR/debug/Suixinji"
fi

if [[ ! -f "$BIN" ]]; then
  echo "Binary not found at $BIN" >&2
  exit 1
fi

echo "==> assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN" "$APP_BUNDLE/Contents/MacOS/Suixinji"

RESOURCE_BUNDLE="$(dirname "$BIN")/Suixinji_Suixinji.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
else
  echo "Resource bundle not found at $RESOURCE_BUNDLE" >&2
  exit 1
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Suixinji</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Not used.</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc signing"
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || echo "(codesign skipped)"

echo "==> built: $APP_BUNDLE"
echo "Run with: open \"$APP_BUNDLE\"  (first time: right-click -> Open to bypass Gatekeeper)"
