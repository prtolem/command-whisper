#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/outputs/Command Whisper.app"

"$ROOT_DIR/scripts/test.sh"
"$ROOT_DIR/scripts/build-app.sh"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
plutil -lint "$APP_DIR/Contents/Info.plist"
"$APP_DIR/Contents/MacOS/CommandWhisper" --self-test
