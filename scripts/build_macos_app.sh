#!/usr/bin/env bash
# macOS app bundle build notes:
# - Input app bundle expected at: base-love2d-images/love.app
# - Required tools: zip, cp, sed
# - Output is an unsigned .app bundle plus a zip archive for sharing.
# - Since the bundle is unsigned, testers on macOS may need to use
#   "Right Click -> Open" the first time, or remove quarantine attributes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-PPUX}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
BASE_RUNTIME_DIR="${BASE_RUNTIME_DIR:-$ROOT_DIR/base-love2d-images}"
BASE_APP_ZIP="${BASE_APP_ZIP:-$BASE_RUNTIME_DIR/love-11.5-macos.zip}"
BASE_APP_URL="${BASE_APP_URL:-https://github.com/love2d/love/releases/download/11.5/love-11.5-macos.zip}"
BASE_APP="${BASE_APP:-$BASE_RUNTIME_DIR/love.app}"
OUT_DIR="${OUT_DIR:-$BUILD_DIR/macos}"
APP_BUNDLE="${APP_BUNDLE:-$OUT_DIR/${APP_NAME}.app}"
OUT_ZIP="${OUT_ZIP:-$OUT_DIR/${APP_NAME}-macos.zip}"

sanitize_bundle_id() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/./g; s/^\.//; s/\.$//; s/\.\.+/./g'
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

replace_plist_string() {
  local plist_path="$1"
  local key_name="$2"
  local key_value="$3"
  local escaped
  escaped="$(escape_sed_replacement "$key_value")"
  sed -i.bak \
    -e "/<key>${key_name//\//\\/}<\/key>/{n;s#<string>.*</string>#<string>${escaped}</string>#;}" \
    "$plist_path"
  rm -f "${plist_path}.bak"
}

APP_BUNDLE_ID="${APP_BUNDLE_ID:-org.ppux.$(sanitize_bundle_id "$APP_NAME")}"
APP_VERSION="${APP_VERSION:-}"

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

ensure_base_app() {
  mkdir -p "$BASE_RUNTIME_DIR"

  if [[ -d "$BASE_APP" ]]; then
    return
  fi

  if [[ ! -f "$BASE_APP_ZIP" ]]; then
    echo "Downloading macOS runtime: $BASE_APP_URL"
    download_file "$BASE_APP_URL" "$BASE_APP_ZIP"
  fi

  echo "Extracting macOS runtime to: $BASE_RUNTIME_DIR"
  extract_zip "$BASE_APP_ZIP" "$BASE_RUNTIME_DIR"

  if [[ ! -d "$BASE_APP" ]]; then
    echo "macOS runtime extraction did not produce: $BASE_APP" >&2
    exit 1
  fi
}

ensure_base_app

LOVE_ARCHIVE="$("$ROOT_DIR/scripts/build_love_archive.sh")"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$OUT_DIR"
cp -a "$BASE_APP" "$APP_BUNDLE"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing Info.plist in copied app bundle: $INFO_PLIST" >&2
  exit 1
fi

replace_plist_string "$INFO_PLIST" "CFBundleName" "$APP_NAME"
replace_plist_string "$INFO_PLIST" "CFBundleIdentifier" "$APP_BUNDLE_ID"
if [[ -n "$APP_VERSION" ]]; then
  replace_plist_string "$INFO_PLIST" "CFBundleShortVersionString" "$APP_VERSION"
fi

cp "$LOVE_ARCHIVE" "$RESOURCES_DIR/game.love"

rm -f "$OUT_ZIP"
(
  cd "$OUT_DIR"
  zip -qry -y "$OUT_ZIP" "${APP_NAME}.app"
)

echo "macOS app bundle created at: $APP_BUNDLE"
echo "macOS zip created at: $OUT_ZIP"
