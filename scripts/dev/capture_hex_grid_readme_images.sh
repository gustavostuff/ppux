#!/usr/bin/env bash
# Regenerate README hex-grid modal PNGs (crop modal, 2x nearest).
#
# Usage (from repo root or anywhere):
#   ./scripts/dev/capture_hex_grid_readme_images.sh

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
if [[ ! -f scripts/dev/capture_hex_grid_readme_images.lua ]]; then
  echo "Error: missing scripts/dev/capture_hex_grid_readme_images.lua" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/img/readme_images"

echo "==> Capturing hex-grid modals (2x) via LOVE"
love . --capture-hex-grids

echo "Done. PNGs in $ROOT_DIR/img/readme_images/{edit_palette_rom_address,add_oam_sprite,set_nametable_range}.png"
