#!/usr/bin/env bash
# Generate README window-link badges.png (7x7 badges, 3x nearest).
# Standalone Love2D app — does not boot PPUX.
#
# Usage (from repo root or anywhere):
#   ./scripts/dev/capture_badges_readme_images.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

GAME_DIR="$ROOT_DIR/scripts/dev/capture_badges_readme_images"

if ! command -v love >/dev/null 2>&1; then
  echo "Error: 'love' command not found." >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: 'ffmpeg' command not found." >&2
  exit 1
fi
if [[ ! -f "$GAME_DIR/main.lua" ]]; then
  echo "Error: missing $GAME_DIR/main.lua" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/img/readme_images"

echo "==> Capturing badges.png (3x) via standalone LOVE"
love "$GAME_DIR"

echo "Done. PNG in $ROOT_DIR/img/readme_images/badges.png"
