#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
VERSION="2.10.0"
EXPECTED_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
ARCHIVE="$ROOT_DIR/work/Sparkle-$VERSION.tar.xz"
DESTINATION="$ROOT_DIR/work/Sparkle-$VERSION"
URL="https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"

if [[ -d "$DESTINATION/Sparkle.framework" ]]; then
    echo "$DESTINATION"
    exit 0
fi

mkdir -p "$ROOT_DIR/work"
if [[ ! -f "$ARCHIVE" ]]; then
    curl --silent --show-error --location --fail --output "$ARCHIVE" "$URL"
fi

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    echo "Sparkle checksum mismatch" >&2
    exit 1
fi

mkdir -p "$DESTINATION"
tar -xf "$ARCHIVE" -C "$DESTINATION"
echo "$DESTINATION"
