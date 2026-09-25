#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
VERSION="${APP_VERSION:-0.3.7}"
APP_DIR="$ROOT_DIR/outputs/Command Whisper.app"
ZIP_PATH="$ROOT_DIR/outputs/Command-Whisper-$VERSION.zip"
DMG_PATH="$ROOT_DIR/outputs/Command-Whisper-$VERSION.dmg"
DMG_ROOT="$ROOT_DIR/work/dmg-root"

"$ROOT_DIR/scripts/build-app.sh"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
ditto "$APP_DIR" "$DMG_ROOT/Command Whisper.app"
cp "$ROOT_DIR/App/Установка.txt" "$DMG_ROOT/Прочти перед установкой.txt"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -quiet -volname "Command Whisper $VERSION" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"

echo "$ZIP_PATH"
echo "$DMG_PATH"
