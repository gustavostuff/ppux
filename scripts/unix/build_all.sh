#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="${APP_NAME:-PPUX}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
source "$ROOT_DIR/scripts/unix/version_utils.sh"
APP_VERSION="${APP_VERSION:-$(read_app_version "$ROOT_DIR")}"
BUILD_VERSION_DIR="${BUILD_VERSION_DIR:-$(resolve_build_version_dir "$ROOT_DIR" "$BUILD_DIR" "$APP_VERSION")}"
VERSION_SUFFIX="${APP_VERSION:+-$APP_VERSION}"

export BUILD_VERSION_DIR

WINDOWS_OUT_ZIP="${WINDOWS_OUT_ZIP:-$BUILD_VERSION_DIR/${APP_NAME}${VERSION_SUFFIX}-win64.zip}"
LINUX_OUT_DIR="${LINUX_OUT_DIR:-$BUILD_VERSION_DIR/${APP_NAME}${VERSION_SUFFIX}-linux-x86_64}"
LINUX_OUT_ZIP="${LINUX_OUT_ZIP:-$BUILD_VERSION_DIR/${APP_NAME}${VERSION_SUFFIX}-linux-x86_64.zip}"
LINUX_OUT_APPIMAGE="${LINUX_OUT_APPIMAGE:-$BUILD_VERSION_DIR/${APP_NAME}${VERSION_SUFFIX}-x86_64.AppImage}"
MACOS_OUT_ZIP="${MACOS_OUT_ZIP:-$BUILD_VERSION_DIR/${APP_NAME}${VERSION_SUFFIX}-macos.zip}"

# Default Linux package is the portable folder (+ zip). Set BUILD_LINUX_APPIMAGE=1
# to also (or only, if BUILD_LINUX_PORTABLE=0) build the AppImage.
BUILD_LINUX_PORTABLE="${BUILD_LINUX_PORTABLE:-1}"
BUILD_LINUX_APPIMAGE="${BUILD_LINUX_APPIMAGE:-0}"

echo "Building version ${APP_VERSION:-unversioned} into: $BUILD_VERSION_DIR"

echo "building for windows"
"$ROOT_DIR/scripts/unix/build_windows.sh"

echo "building for linux (portable folder)"
if [[ "$BUILD_LINUX_PORTABLE" == "1" ]]; then
  "$ROOT_DIR/scripts/unix/build_linux_portable.sh"
else
  echo "skipping linux portable (BUILD_LINUX_PORTABLE=$BUILD_LINUX_PORTABLE)"
fi

if [[ "$BUILD_LINUX_APPIMAGE" == "1" ]]; then
  echo "building for linux (AppImage)"
  "$ROOT_DIR/scripts/unix/build_linux_appimage.sh"
fi

echo "building for macos"
"$ROOT_DIR/scripts/unix/build_macos_app.sh"

echo
echo "all completed"
echo "Version folder: $BUILD_VERSION_DIR"
if [[ "$BUILD_LINUX_PORTABLE" == "1" ]]; then
  echo "Linux portable: $LINUX_OUT_DIR"
  echo "Linux zip: $LINUX_OUT_ZIP"
fi
if [[ "$BUILD_LINUX_APPIMAGE" == "1" ]]; then
  echo "Linux AppImage: $LINUX_OUT_APPIMAGE"
fi
