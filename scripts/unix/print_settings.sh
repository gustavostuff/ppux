#!/usr/bin/env bash
# Print PPUX settings.lua contents from known locations (same search order as remove_linux_settings.sh).
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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYSTEM_SETTINGS="${LOVE_DATA_DIR}/${SETTINGS_FILE}"
APPIMAGE_SETTINGS="${APP_DATA_DIR}/${SETTINGS_FILE}"
OLD_CONFIG_SETTINGS="${LEGACY_CONFIG_DIR}/${SETTINGS_FILE}"
LEGACY_SETTINGS="${REPO_ROOT}/${SETTINGS_FILE}"

candidates=(
  "$SYSTEM_SETTINGS"
  "$APPIMAGE_SETTINGS"
  "$OLD_CONFIG_SETTINGS"
  "$LEGACY_SETTINGS"
)

any=0
for path in "${candidates[@]}"; do
  if [[ -f "$path" ]]; then
    any=1
    echo "=== ${path} ==="
    cat -- "$path"
    echo
  fi
done

if [[ "$any" -eq 0 ]]; then
  echo "No settings file found. Checked:" >&2
  printf '  %s\n' "${candidates[@]}" >&2
  exit 1
fi
