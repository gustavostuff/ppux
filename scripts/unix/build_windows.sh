#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="${APP_NAME:-PPUX}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
source "$ROOT_DIR/scripts/unix/version_utils.sh"
APP_VERSION="${APP_VERSION:-$(read_app_version "$ROOT_DIR")}"
VERSION_SUFFIX="${APP_VERSION:+-$APP_VERSION}"
BASE_RUNTIME_DIR="${BASE_RUNTIME_DIR:-$ROOT_DIR/base-love2d-images}"
WIN_RUNTIME_ZIP="${WIN_RUNTIME_ZIP:-$BASE_RUNTIME_DIR/love-11.5-win64.zip}"
WIN_RUNTIME_URL="${WIN_RUNTIME_URL:-https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip}"
WIN_RUNTIME_DIR="${WIN_RUNTIME_DIR:-$ROOT_DIR/base-love2d-images/love-11.5-win64}"
PACKAGE_STAGE_DIR="${PACKAGE_STAGE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/ppux-win64.XXXXXX")/${APP_NAME}-win64}"
OUT_ZIP="${OUT_ZIP:-$BUILD_DIR/${APP_NAME}${VERSION_SUFFIX}-win64.zip}"

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
    return
  fi

  if [[ ! -f "$WIN_RUNTIME_ZIP" ]]; then
    echo "Downloading runtime..."
    download_file "$WIN_RUNTIME_URL" "$WIN_RUNTIME_ZIP"
  fi

  echo "Extracting runtime..."
  extract_zip "$WIN_RUNTIME_ZIP" "$BASE_RUNTIME_DIR"

  if [[ ! -f "$WIN_RUNTIME_DIR/love.exe" ]]; then
    echo "Windows runtime extraction did not produce: $WIN_RUNTIME_DIR/love.exe" >&2
    exit 1
  fi
}

ensure_windows_runtime

update_readme_version "$ROOT_DIR" "$APP_VERSION"
LOVE_ARCHIVE="$("$ROOT_DIR/scripts/unix/build_love_archive.sh" 2>/dev/null)"

rm -rf "$PACKAGE_STAGE_DIR"
mkdir -p "$PACKAGE_STAGE_DIR"
mkdir -p "$BUILD_DIR"

cat "$WIN_RUNTIME_DIR/love.exe" "$LOVE_ARCHIVE" > "$PACKAGE_STAGE_DIR/${APP_NAME}.exe"

for dll in OpenAL32.dll SDL2.dll love.dll lua51.dll mpg123.dll msvcp120.dll msvcr120.dll; do
  cp "$WIN_RUNTIME_DIR/$dll" "$PACKAGE_STAGE_DIR/"
done

if [[ -f "$WIN_RUNTIME_DIR/license.txt" ]]; then
  cp "$WIN_RUNTIME_DIR/license.txt" "$PACKAGE_STAGE_DIR/"
fi

rm -f "$OUT_ZIP"
(
  cd "$(dirname "$PACKAGE_STAGE_DIR")"
  zip -qry "$OUT_ZIP" "$(basename "$PACKAGE_STAGE_DIR")"
)
rm -rf "$PACKAGE_STAGE_DIR"

echo "Done: $OUT_ZIP"
