#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-PPUX}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
source "$ROOT_DIR/scripts/version_utils.sh"
APP_VERSION="${APP_VERSION:-$(read_app_version "$ROOT_DIR")}"
VERSION_SUFFIX="${APP_VERSION:+-$APP_VERSION}"

WINDOWS_OUT_ZIP="${WINDOWS_OUT_ZIP:-$BUILD_DIR/${APP_NAME}${VERSION_SUFFIX}-win64.zip}"
LINUX_OUT_APPIMAGE="${LINUX_OUT_APPIMAGE:-$BUILD_DIR/${APP_NAME}${VERSION_SUFFIX}-x86_64.AppImage}"
MACOS_OUT_ZIP="${MACOS_OUT_ZIP:-$BUILD_DIR/${APP_NAME}${VERSION_SUFFIX}-macos.zip}"

echo "building for windows"
"$ROOT_DIR/scripts/build_windows.sh"
echo "building for linux"
"$ROOT_DIR/scripts/build_linux_appimage.sh"
echo "building for macos"
"$ROOT_DIR/scripts/build_macos_app.sh"

echo
echo "all completed"
