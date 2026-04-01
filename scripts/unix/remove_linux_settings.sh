#!/usr/bin/env bash
set -euo pipefail

APP_IDENTITY="ppux"
APP_NAME="PPUX"
SETTINGS_FILE="settings.lua"

if [[ -n "${XDG_DATA_HOME:-}" ]]; then
  LOVE_DATA_DIR="${XDG_DATA_HOME}/love/${APP_IDENTITY}"
  APP_DATA_DIR="${XDG_DATA_HOME}/${APP_IDENTITY}"
else
  LOVE_DATA_DIR="${HOME}/.local/share/love/${APP_IDENTITY}"
  APP_DATA_DIR="${HOME}/.local/share/${APP_IDENTITY}"
fi

if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
  LEGACY_CONFIG_DIR="${XDG_CONFIG_HOME}/${APP_NAME}"
else
  LEGACY_CONFIG_DIR="${HOME}/.config/${APP_NAME}"
fi

SYSTEM_SETTINGS="${LOVE_DATA_DIR}/${SETTINGS_FILE}"
APPIMAGE_SETTINGS="${APP_DATA_DIR}/${SETTINGS_FILE}"
OLD_CONFIG_SETTINGS="${LEGACY_CONFIG_DIR}/${SETTINGS_FILE}"
LEGACY_SETTINGS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/${SETTINGS_FILE}"

removed=0

for candidate in "$SYSTEM_SETTINGS" "$APPIMAGE_SETTINGS" "$OLD_CONFIG_SETTINGS" "$LEGACY_SETTINGS"; do
  if [[ -f "$candidate" ]]; then
    rm -f "$candidate"
    echo "Removed settings file: $candidate"
    removed=1
  fi
done

if [[ "$removed" -eq 0 ]]; then
  echo "No settings files found in:"
  echo "  $SYSTEM_SETTINGS"
  echo "  $APPIMAGE_SETTINGS"
  echo "  $OLD_CONFIG_SETTINGS"
  echo "  $LEGACY_SETTINGS"
  exit 0
fi
