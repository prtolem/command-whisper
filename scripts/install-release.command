#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SOURCE_APP="$SCRIPT_DIR/Command Whisper.app"
INSTALL_ROOT="${COMMAND_WHISPER_INSTALL_DIR:-${HOME}/Applications}"
INSTALLED_APP="$INSTALL_ROOT/Command Whisper.app"

finish() {
    local exit_code="$?"
    if [[ "${COMMAND_WHISPER_NONINTERACTIVE:-0}" != "1" ]]; then
        if [[ "$exit_code" == "0" ]]; then
            echo
            echo "Готово. Command Whisper установлен и запущен."
        else
            echo
            echo "Установка не завершена. Код ошибки: $exit_code"
        fi
        echo "Нажмите любую клавишу, чтобы закрыть окно."
        read -k 1
    fi
}
trap finish EXIT

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Не найден Command Whisper.app рядом с установщиком."
    exit 1
fi

mkdir -p "$INSTALL_ROOT"
pkill -x CommandWhisper 2>/dev/null || true

if [[ -e "$INSTALLED_APP" ]]; then
    TRASH_ROOT="${HOME}/.Trash"
    mkdir -p "$TRASH_ROOT"
    BACKUP_APP="$TRASH_ROOT/Command Whisper $(date +%Y-%m-%d_%H-%M-%S).app"
    mv "$INSTALLED_APP" "$BACKUP_APP"
    echo "Предыдущая версия перемещена в Корзину."
fi

ditto "$SOURCE_APP" "$INSTALLED_APP"
xattr -dr com.apple.quarantine "$INSTALLED_APP" 2>/dev/null || true
codesign --verify --deep --strict "$INSTALLED_APP"

if [[ "${COMMAND_WHISPER_SKIP_LAUNCH:-0}" != "1" ]]; then
    open "$INSTALLED_APP"
fi

echo "Установлено: $INSTALLED_APP"
