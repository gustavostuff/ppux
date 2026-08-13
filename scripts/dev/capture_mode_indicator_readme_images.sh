#!/usr/bin/env bash
# Regenerate README tile/edit mode indicator PNGs
# (bottom-right 160x90 crop, 2x nearest -> 320x180).
#
# Usage (from repo root or anywhere):
#   ./scripts/dev/capture_mode_indicator_readme_images.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v love >/dev/null 2>&1; then
  echo "Error: 'love' command not found." >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: 'ffmpeg' command not found." >&2
  exit 1
fi
if [[ ! -f scripts/dev/capture_mode_indicator_readme_images.lua ]]; then
  echo "Error: missing scripts/dev/capture_mode_indicator_readme_images.lua" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/img/readme_images"

echo "==> Capturing mode indicators (160x90 crop, 2x -> 320x180) via LOVE"
love . --capture-mode-indicators

echo "Done. PNGs in $ROOT_DIR/img/readme_images/{tile,edit}_mode_indicator.png"
