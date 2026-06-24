#!/usr/bin/env bash
# Move legacy flat build artifacts into build/<version>/ folders.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
APP_NAME="${APP_NAME:-PPUX}"
source "$ROOT_DIR/scripts/unix/version_utils.sh"

CURRENT_VERSION="$(read_app_version "$ROOT_DIR")"

move_into_version_dir() {
  local version="$1"
  local file_path="$2"
  local dest_dir="$BUILD_DIR/$version"
  local base_name
  base_name="$(basename "$file_path")"

  mkdir -p "$dest_dir"

  if [[ -e "$dest_dir/$base_name" ]]; then
    if [[ "$base_name" == "${APP_NAME}.love" ]]; then
      rm -f "$file_path"
      echo "removed duplicate: $base_name (already in $dest_dir/)"
      return 0
    fi
    echo "skip (already exists): $dest_dir/$base_name"
    return 0
  fi

  mv "$file_path" "$dest_dir/$base_name"
  echo "moved: $base_name -> $dest_dir/"
}

if [[ ! -d "$BUILD_DIR" ]]; then
  echo "Nothing to reorganize: $BUILD_DIR does not exist."
  exit 0
fi

moved=0
skipped=0

shopt -s nullglob
for file_path in "$BUILD_DIR"/${APP_NAME}-* "$BUILD_DIR"/${APP_NAME}.love; do
  [[ -f "$file_path" ]] || continue

  base_name="$(basename "$file_path")"
  version=""

  if [[ "$base_name" =~ ^${APP_NAME}-([0-9]+\.[0-9]+\.[0-9]+)- ]]; then
    version="${BASH_REMATCH[1]}"
  elif [[ "$base_name" == "${APP_NAME}.love" && -n "$CURRENT_VERSION" ]]; then
    version="$CURRENT_VERSION"
  fi

  if [[ -z "$version" ]]; then
    echo "skip (no version): $base_name"
    skipped=$((skipped + 1))
    continue
  fi

  if move_into_version_dir "$version" "$file_path"; then
    moved=$((moved + 1))
  else
    skipped=$((skipped + 1))
  fi
done
shopt -u nullglob

echo
echo "Reorganize complete under: $BUILD_DIR"
echo "Moved: $moved  Skipped: $skipped"
