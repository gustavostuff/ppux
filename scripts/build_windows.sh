#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-PPUX}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
BASE_RUNTIME_DIR="${BASE_RUNTIME_DIR:-$ROOT_DIR/base-love2d-images}"
WIN_RUNTIME_ZIP="${WIN_RUNTIME_ZIP:-$BASE_RUNTIME_DIR/love-11.5-win64.zip}"
WIN_RUNTIME_URL="${WIN_RUNTIME_URL:-https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip}"
WIN_RUNTIME_DIR="${WIN_RUNTIME_DIR:-$ROOT_DIR/base-love2d-images/love-11.5-win64}"
OUT_DIR="${OUT_DIR:-$BUILD_DIR/windows/${APP_NAME}-win64}"

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

extract_zip() {
  local archive="$1"
  local destination="$2"

  if command -v unzip >/dev/null 2>&1; then
    unzip -q -o "$archive" -d "$destination"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m zipfile -e "$archive" "$destination"
  else
    echo "Missing extractor. Install unzip or python3." >&2
    exit 1
  fi
}

ensure_windows_runtime() {
  mkdir -p "$BASE_RUNTIME_DIR"

  if [[ -f "$WIN_RUNTIME_DIR/love.exe" ]]; then
    echo "Using existing Windows runtime at: $WIN_RUNTIME_DIR"
    return
  fi

  if [[ ! -f "$WIN_RUNTIME_ZIP" ]]; then
    echo "Downloading Windows runtime: $WIN_RUNTIME_URL"
    download_file "$WIN_RUNTIME_URL" "$WIN_RUNTIME_ZIP"
  fi

  echo "Extracting Windows runtime to: $BASE_RUNTIME_DIR"
  extract_zip "$WIN_RUNTIME_ZIP" "$BASE_RUNTIME_DIR"

  if [[ ! -f "$WIN_RUNTIME_DIR/love.exe" ]]; then
    echo "Windows runtime extraction did not produce: $WIN_RUNTIME_DIR/love.exe" >&2
    exit 1
  fi
}

echo "Ensuring Windows runtime..."
ensure_windows_runtime

echo "Building LOVE archive..."
LOVE_ARCHIVE="$("$ROOT_DIR/scripts/build_love_archive.sh")"

echo "Preparing Windows output directory: $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "Fusing executable..."
cat "$WIN_RUNTIME_DIR/love.exe" "$LOVE_ARCHIVE" > "$OUT_DIR/${APP_NAME}.exe"

echo "Copying runtime DLLs..."
for dll in OpenAL32.dll SDL2.dll love.dll lua51.dll mpg123.dll msvcp120.dll msvcr120.dll; do
  cp "$WIN_RUNTIME_DIR/$dll" "$OUT_DIR/"
done

if [[ -f "$WIN_RUNTIME_DIR/license.txt" ]]; then
  cp "$WIN_RUNTIME_DIR/license.txt" "$OUT_DIR/"
fi

echo "Windows build created at: $OUT_DIR"
