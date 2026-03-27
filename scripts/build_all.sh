#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-PPUX}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"

WINDOWS_OUT_DIR="${WINDOWS_OUT_DIR:-$BUILD_DIR/windows/${APP_NAME}-win64}"
LINUX_OUT_APPIMAGE="${LINUX_OUT_APPIMAGE:-$BUILD_DIR/linux/${APP_NAME}-x86_64.AppImage}"
MACOS_OUT_APP="${MACOS_OUT_APP:-$BUILD_DIR/macos/${APP_NAME}.app}"
MACOS_OUT_ZIP="${MACOS_OUT_ZIP:-$BUILD_DIR/macos/${APP_NAME}-macos.zip}"

clear

echo "-------------------------------------------------------------------------------------"
echo "Building Windows package..."
"$ROOT_DIR/scripts/build_windows.sh"

echo "-------------------------------------------------------------------------------------"
echo "Building Linux AppImage..."
"$ROOT_DIR/scripts/build_linux_appimage.sh"

echo "-------------------------------------------------------------------------------------"
echo "Building macOS app bundle..."
"$ROOT_DIR/scripts/build_macos_app.sh"

echo
echo "Build outputs:"
echo "  Windows: $WINDOWS_OUT_DIR"
echo "  Linux:   $LINUX_OUT_APPIMAGE"
echo "  macOS:   $MACOS_OUT_APP"
echo "  macOS zip: $MACOS_OUT_ZIP"
