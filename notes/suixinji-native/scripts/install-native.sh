#!/usr/bin/env bash
# Install 随心记 native to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh --release

APP_NAME="随心记"
APP_BUNDLE="dist/${APP_NAME}.app"

echo "==> copying to /Applications"
rm -rf "/Applications/${APP_NAME}.app"
cp -R "$APP_BUNDLE" "/Applications/"

echo "Installed. First launch: right-click the app in Finder -> Open (Gatekeeper),"
echo "or: xattr -dr com.apple.quarantine \"/Applications/${APP_NAME}.app\""
echo "Then press Cmd+Enter anywhere (including fullscreen apps) to toggle the panel."
