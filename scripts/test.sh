#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
TEST_BIN="$ROOT_DIR/work/text-cleaner-tests"
mkdir -p "$ROOT_DIR/work/module-cache"

clang -fobjc-arc -fmodules -fmodules-cache-path="$ROOT_DIR/work/module-cache" -fblocks -framework Foundation \
    -I "$ROOT_DIR/Sources/CommandWhisper" \
    "$ROOT_DIR/Tests/TextCleanerTests.m" \
    "$ROOT_DIR/Sources/CommandWhisper/TextCleaner.m" \
    -o "$TEST_BIN"
"$TEST_BIN"
