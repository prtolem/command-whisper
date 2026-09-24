#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/outputs/Command Whisper.app"
BUILD_DIR="$ROOT_DIR/work/build"
SPARKLE_DIR="$($ROOT_DIR/scripts/fetch-sparkle.sh)"
APP_VERSION="${APP_VERSION:-0.3.5}"
APP_BUILD="${APP_BUILD:-8}"

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

LOCAL_SIGNING_IDENTITY="Command Whisper Local Signing"
LOCAL_KEYCHAIN="$ROOT_DIR/work/cw-build.keychain-db"
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}"
if [[ -f "$LOCAL_KEYCHAIN" && -f "$ROOT_DIR/work/command-whisper-signing-password" ]]; then
    security unlock-keychain -p "$(<"$ROOT_DIR/work/command-whisper-signing-password")" "$LOCAL_KEYCHAIN" 2>/dev/null || true
fi
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    LOCAL_IDENTITY_HASH=""
    if [[ -f "$LOCAL_KEYCHAIN" ]]; then
        LOCAL_IDENTITY_HASH="$(security find-identity -v -p codesigning "$LOCAL_KEYCHAIN" 2>/dev/null | awk -v name="$LOCAL_SIGNING_IDENTITY" 'index($0, "\"" name "\"") { print $2; exit }')"
    fi
    if [[ -n "$LOCAL_IDENTITY_HASH" ]]; then
        SIGN_IDENTITY="$LOCAL_IDENTITY_HASH"
        SIGN_KEYCHAIN="$LOCAL_KEYCHAIN"
        if [[ -f "$ROOT_DIR/work/command-whisper-signing-password" ]]; then
            security unlock-keychain -p "$(<"$ROOT_DIR/work/command-whisper-signing-password")" "$LOCAL_KEYCHAIN"
        fi
    elif security find-identity -v -p codesigning | grep -Fq "\"$LOCAL_SIGNING_IDENTITY\""; then
        SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -v name="$LOCAL_SIGNING_IDENTITY" 'index($0, "\"" name "\"") { print $2; exit }')"
    else
        SIGN_IDENTITY="-"
    fi
fi
echo "Signing with identity: $SIGN_IDENTITY"
KEYCHAIN_ARGS=()
if [[ -n "$SIGN_KEYCHAIN" ]]; then
    KEYCHAIN_ARGS=(--keychain "$SIGN_KEYCHAIN")
fi
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP_DIR/Contents/Frameworks/Sparkle.framework"
    codesign --force --deep --sign - --identifier ru.prtolem.CommandWhisper "$APP_DIR"
elif [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "${KEYCHAIN_ARGS[@]}" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "${KEYCHAIN_ARGS[@]}" --identifier ru.prtolem.CommandWhisper "$APP_DIR"
else
    codesign --force --deep --sign "$SIGN_IDENTITY" "${KEYCHAIN_ARGS[@]}" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
    codesign --force --deep --sign "$SIGN_IDENTITY" "${KEYCHAIN_ARGS[@]}" --identifier ru.prtolem.CommandWhisper "$APP_DIR"
fi
echo "$APP_DIR"
