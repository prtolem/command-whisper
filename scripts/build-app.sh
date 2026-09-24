#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/outputs/Command Whisper.app"
BUILD_DIR="$ROOT_DIR/work/build"
SPARKLE_DIR="$($ROOT_DIR/scripts/fetch-sparkle.sh)"
APP_VERSION="${APP_VERSION:-0.3.0}"
APP_BUILD="${APP_BUILD:-3}"

cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$ROOT_DIR/work/module-cache"
clang -fobjc-arc -fmodules -fmodules-cache-path="$ROOT_DIR/work/module-cache" -fblocks -O2 -mmacosx-version-min=13.0 \
    -arch arm64 -arch x86_64 \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework AVFoundation \
    -framework Accelerate \
    -framework Speech \
    -F "$SPARKLE_DIR" \
    -framework Sparkle \
    -Wl,-rpath,@executable_path/../Frameworks \
    -I "$ROOT_DIR/Sources/CommandWhisper" \
    "$ROOT_DIR/Sources/CommandWhisper/main.m" \
    "$ROOT_DIR/Sources/CommandWhisper/TextCleaner.m" \
    -o "$BUILD_DIR/CommandWhisper"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks"
cp "$BUILD_DIR/CommandWhisper" "$APP_DIR/Contents/MacOS/CommandWhisper"
cp "$ROOT_DIR/App/Info.plist" "$APP_DIR/Contents/Info.plist"
ditto "$SPARKLE_DIR/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$APP_DIR/Contents/Info.plist"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP_DIR/Contents/Frameworks/Sparkle.framework"
    codesign --force --deep --sign - --identifier ru.prtolem.CommandWhisper "$APP_DIR"
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" --identifier ru.prtolem.CommandWhisper "$APP_DIR"
fi
echo "$APP_DIR"
