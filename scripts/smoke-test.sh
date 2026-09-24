#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/outputs/Command Whisper.app"

"$ROOT_DIR/scripts/test.sh"
"$ROOT_DIR/scripts/build-app.sh"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
plutil -lint "$APP_DIR/Contents/Info.plist"
"$APP_DIR/Contents/MacOS/CommandWhisper" --self-test

INSTALL_TEST_ROOT="$ROOT_DIR/work/install-smoke"
rm -rf "$INSTALL_TEST_ROOT"
mkdir -p "$INSTALL_TEST_ROOT/dmg"
ditto "$APP_DIR" "$INSTALL_TEST_ROOT/dmg/Command Whisper.app"
cp "$ROOT_DIR/scripts/install-release.command" "$INSTALL_TEST_ROOT/dmg/Install Command Whisper.command"
chmod +x "$INSTALL_TEST_ROOT/dmg/Install Command Whisper.command"
COMMAND_WHISPER_INSTALL_DIR="$INSTALL_TEST_ROOT/Applications" \
COMMAND_WHISPER_NONINTERACTIVE=1 \
COMMAND_WHISPER_SKIP_LAUNCH=1 \
    "$INSTALL_TEST_ROOT/dmg/Install Command Whisper.command"
codesign --verify --deep --strict "$INSTALL_TEST_ROOT/Applications/Command Whisper.app"
