#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-PPUX}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
LOVE_ARCHIVE="${LOVE_ARCHIVE:-$BUILD_DIR/${APP_NAME}.love}"

mkdir -p "$BUILD_DIR"

tmp_file_list="$(mktemp)"
cleanup() {
  rm -f "$tmp_file_list"
}
trap cleanup EXIT

echo "Preparing LOVE archive file list..." >&2

(
  cd "$ROOT_DIR"
  find . \
    \( -path './.git' \
    -o -path './build' \
    -o -path './base-love2d-images' \
    -o -path './docs' \
    -o -path './examples' \
    -o -path './scripts' \
    -o -path './test' \
    -o -path './tmp' \
    -o -path './bkps' \) -prune -o \
    -type f \
    ! -name '*.sh' \
    ! -name '*.love' \
    ! -name '*.AppImage' \
    -print \
  | sed 's#^\./##' \
  | LC_ALL=C sort
) > "$tmp_file_list"

file_count="$(wc -l < "$tmp_file_list" | tr -d '[:space:]')"
echo "Creating LOVE archive with ${file_count:-0} files..." >&2

rm -f "$LOVE_ARCHIVE"
(
  cd "$ROOT_DIR"
  zip -q -9 "$LOVE_ARCHIVE" -@ < "$tmp_file_list"
)

echo "LOVE archive created at: $LOVE_ARCHIVE" >&2

printf '%s\n' "$LOVE_ARCHIVE"
