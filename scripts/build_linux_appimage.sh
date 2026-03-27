#!/usr/bin/env bash
# Linux AppImage build notes:
# - Required tool: appimagetool
# - Required tool: zip (used by scripts/build_love_archive.sh)
# - Required core utils: cat, cp, chmod, dd, mv, rm, sed
# - Input base image expected at: base-love2d-images/love-linux-11.5-x86_64.AppImage
# - This script rebuilds the AppImage fully offline by extracting the runtime
#   from the base AppImage and passing it to appimagetool via --runtime-file.
# - To run the final AppImage on some Linux distros, FUSE/AppImage runtime
#   support may still be needed. If direct launch fails, try:
#     ./PPUX-x86_64.AppImage --appimage-extract-and-run
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-PPUX}"
APP_COMMENT="${APP_COMMENT:-Open Source NES Art Editor}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
BASE_RUNTIME_DIR="${BASE_RUNTIME_DIR:-$ROOT_DIR/base-love2d-images}"
BASE_APPIMAGE="${BASE_APPIMAGE:-$BASE_RUNTIME_DIR/love-linux-11.5-x86_64.AppImage}"
BASE_APPIMAGE_URL="${BASE_APPIMAGE_URL:-https://github.com/love2d/love/releases/download/11.5/love-11.5-x86_64.AppImage}"
OUT_DIR="${OUT_DIR:-$BUILD_DIR/linux}"
WORK_DIR="${WORK_DIR:-$OUT_DIR/appimage-work}"
OUT_APPIMAGE="${OUT_APPIMAGE:-$OUT_DIR/${APP_NAME}-x86_64.AppImage}"

download_file() {
  local url="$1"
  local destination="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -L --fail -o "$destination" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$destination" "$url"
  else
    echo "Missing downloader. Install curl or wget." >&2
    exit 1
  fi
}

ensure_base_appimage() {
  mkdir -p "$BASE_RUNTIME_DIR"

  if [[ -f "$BASE_APPIMAGE" ]]; then
    chmod +x "$BASE_APPIMAGE"
    return
  fi

  echo "Downloading Linux AppImage runtime: $BASE_APPIMAGE_URL"
  download_file "$BASE_APPIMAGE_URL" "$BASE_APPIMAGE"
  chmod +x "$BASE_APPIMAGE"
}

ensure_base_appimage

if ! command -v appimagetool >/dev/null 2>&1; then
  echo "appimagetool is required but was not found in PATH." >&2
  exit 1
fi

LOVE_ARCHIVE="$("$ROOT_DIR/scripts/build_love_archive.sh")"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$OUT_DIR"

cp "$BASE_APPIMAGE" "$WORK_DIR/love.AppImage"
chmod +x "$WORK_DIR/love.AppImage"
RUNTIME_OFFSET="$("$WORK_DIR/love.AppImage" --appimage-offset)"
RUNTIME_FILE="$WORK_DIR/runtime-x86_64"
dd if="$WORK_DIR/love.AppImage" of="$RUNTIME_FILE" bs=1 count="$RUNTIME_OFFSET" status=none

(
  cd "$WORK_DIR"
  ./love.AppImage --appimage-extract >/dev/null

  mv squashfs-root/bin/love squashfs-root/bin/love.base
  cat squashfs-root/bin/love.base "$LOVE_ARCHIVE" > squashfs-root/bin/love
  chmod +x squashfs-root/bin/love
  rm -f squashfs-root/bin/love.base

  for desktop_file in squashfs-root/love.desktop squashfs-root/share/applications/love.desktop; do
    if [[ -f "$desktop_file" ]]; then
      sed -i \
        -e "s/^Name=.*/Name=${APP_NAME}/" \
        -e "s/^Comment=.*/Comment=${APP_COMMENT}/" \
        "$desktop_file"
    fi
  done

  ARCH=x86_64 appimagetool --runtime-file "$RUNTIME_FILE" --comp gzip -n squashfs-root "$OUT_APPIMAGE" >/dev/null
)

chmod +x "$OUT_APPIMAGE"
echo "Linux AppImage created at: $OUT_APPIMAGE"
