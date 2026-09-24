#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
IDENTITY="Command Whisper Local Signing"
KEY_PATH="$ROOT_DIR/work/command-whisper-signing.key"
CERT_PATH="$ROOT_DIR/work/command-whisper-signing.crt"
P12_PATH="$ROOT_DIR/work/command-whisper-signing.p12"
PASSWORD_PATH="$ROOT_DIR/work/command-whisper-signing-password"
KEYCHAIN_PATH="$ROOT_DIR/work/cw-build.keychain-db"
OPENSSL_BIN="/opt/homebrew/opt/openssl@3/bin/openssl"

if [[ -f "$KEYCHAIN_PATH" ]] && security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -Fq "\"$IDENTITY\""; then
    echo "$IDENTITY"
    exit 0
fi

if [[ ! -x "$OPENSSL_BIN" ]]; then
    OPENSSL_BIN="/usr/bin/openssl"
fi

mkdir -p "$ROOT_DIR/work"
"$OPENSSL_BIN" rand -hex 24 > "$PASSWORD_PATH"
"$OPENSSL_BIN" req -new -newkey rsa:3072 -x509 -sha256 -days 3650 -nodes \
    -config "$ROOT_DIR/App/CodeSigning.cnf" \
    -keyout "$KEY_PATH" \
    -out "$CERT_PATH"
"$OPENSSL_BIN" pkcs12 -export \
    -legacy \
    -inkey "$KEY_PATH" \
    -in "$CERT_PATH" \
    -name "$IDENTITY" \
    -passout "file:$PASSWORD_PATH" \
    -out "$P12_PATH"

if [[ ! -f "$KEYCHAIN_PATH" ]]; then
    security create-keychain -p "$(<"$PASSWORD_PATH")" "$KEYCHAIN_PATH"
fi
security unlock-keychain -p "$(<"$PASSWORD_PATH")" "$KEYCHAIN_PATH"
security import "$P12_PATH" \
    -f pkcs12 \
    -k "$KEYCHAIN_PATH" \
    -P "$(<"$PASSWORD_PATH")" \
    -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN_PATH" "$CERT_PATH"

echo "$IDENTITY"
