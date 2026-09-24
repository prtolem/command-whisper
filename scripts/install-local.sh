#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE_APP="$ROOT_DIR/outputs/Command Whisper.app"
INSTALL_ROOT="${HOME}/Applications"
INSTALLED_APP="$INSTALL_ROOT/Command Whisper.app"

"$ROOT_DIR/scripts/build-app.sh"
mkdir -p "$INSTALL_ROOT"
pkill -x CommandWhisper 2>/dev/null || true
ditto "$SOURCE_APP" "$INSTALLED_APP"
xattr -dr com.apple.quarantine "$INSTALLED_APP" 2>/dev/null || true
open "$INSTALLED_APP"

echo "$INSTALLED_APP"
