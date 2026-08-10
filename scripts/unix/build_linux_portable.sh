#!/usr/bin/env bash
# Linux portable folder build notes:
# - Required tool: zip (used by scripts/unix/build_love_archive.sh and this script)
# - Required tool: patchelf (sets RPATH so top-level PPUX finds ./lib)
# - Required core utils: cat, cp, chmod, rm
# - Input base image expected at: base-love2d-images/love-linux-11.5-x86_64.AppImage
# - Produces a runnable folder (fused native ELF + lib/) and a zip of that folder.
# - Does not require appimagetool. AppImage packaging remains in build_linux_appimage.sh.
#
# Layout:
#   PPUX-<ver>-linux-x86_64/
#     PPUX                 # fused native LÖVE + game.love ELF (run this)
#     lib/                 # LOVE .so files + libppux_sketch.so (RPATH = $ORIGIN/lib)
#     LICENSE
#
# Extra tools (e.g. a PNG processor) can sit next to PPUX in this folder.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="${APP_NAME:-PPUX}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
source "$ROOT_DIR/scripts/unix/version_utils.sh"
APP_VERSION="${APP_VERSION:-$(read_app_version "$ROOT_DIR")}"
BUILD_VERSION_DIR="${BUILD_VERSION_DIR:-$(resolve_build_version_dir "$ROOT_DIR" "$BUILD_DIR" "$APP_VERSION")}"
VERSION_SUFFIX="${APP_VERSION:+-$APP_VERSION}"
BASE_RUNTIME_DIR="${BASE_RUNTIME_DIR:-$ROOT_DIR/base-love2d-images}"
BASE_APPIMAGE="${BASE_APPIMAGE:-$BASE_RUNTIME_DIR/love-linux-11.5-x86_64.AppImage}"
BASE_APPIMAGE_URL="${BASE_APPIMAGE_URL:-https://github.com/love2d/love/releases/download/11.5/love-11.5-x86_64.AppImage}"
WORK_DIR="${WORK_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/ppux-linux-portable.XXXXXX")}"
PACKAGE_NAME="${PACKAGE_NAME:-${APP_NAME}${VERSION_SUFFIX}-linux-x86_64}"
PACKAGE_DIR="${PACKAGE_DIR:-$BUILD_VERSION_DIR/$PACKAGE_NAME}"
OUT_ZIP="${OUT_ZIP:-$BUILD_VERSION_DIR/${PACKAGE_NAME}.zip}"

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

  echo "Downloading runtime..."
  download_file "$BASE_APPIMAGE_URL" "$BASE_APPIMAGE"
  chmod +x "$BASE_APPIMAGE"
}

if ! command -v patchelf >/dev/null 2>&1; then
  echo "patchelf is required to place ${APP_NAME} next to lib/ (RPATH \$ORIGIN/lib)." >&2
  echo "Install patchelf and re-run." >&2
  exit 1
fi

ensure_base_appimage

update_readme_version "$ROOT_DIR" "$APP_VERSION"
LOVE_ARCHIVE="$("$ROOT_DIR/scripts/unix/build_love_archive.sh" 2>/dev/null)"

rm -rf "$WORK_DIR" "$PACKAGE_DIR"
mkdir -p "$WORK_DIR" "$BUILD_VERSION_DIR"

cp "$BASE_APPIMAGE" "$WORK_DIR/love.AppImage"
chmod +x "$WORK_DIR/love.AppImage"

(
  cd "$WORK_DIR"
  ./love.AppImage --appimage-extract >/dev/null

  mkdir -p "$PACKAGE_DIR/lib"
  cat squashfs-root/bin/love "$LOVE_ARCHIVE" > "$PACKAGE_DIR/${APP_NAME}"
  chmod +x "$PACKAGE_DIR/${APP_NAME}"
  # Stock love looks for ../lib (bin/ layout). Point it at ./lib beside the binary.
  patchelf --set-rpath '$ORIGIN/lib' "$PACKAGE_DIR/${APP_NAME}"
  cp -a squashfs-root/lib/. "$PACKAGE_DIR/lib/"
  cp "$ROOT_DIR/LICENSE" "$PACKAGE_DIR/LICENSE"
)

# Sketch PNG helper (LuaJIT FFI). Soft-fail so packaging still works without a C toolchain.
if make -C "$ROOT_DIR/native/ppux_sketch" all; then
  if [[ -f "$ROOT_DIR/native/ppux_sketch/libppux_sketch.so" ]]; then
    cp "$ROOT_DIR/native/ppux_sketch/libppux_sketch.so" "$PACKAGE_DIR/lib/libppux_sketch.so"
  fi
else
  echo "warning: native/ppux_sketch build failed; portable package will use Lua PNG import" >&2
fi

rm -f "$OUT_ZIP"
(
  cd "$BUILD_VERSION_DIR"
  zip -qry "$OUT_ZIP" "$PACKAGE_NAME"
)

rm -rf "$WORK_DIR"
echo "Done: $PACKAGE_DIR"
echo "Zip: $OUT_ZIP"
echo "Version folder: $BUILD_VERSION_DIR"
