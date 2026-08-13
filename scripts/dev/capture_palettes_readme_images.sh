#!/usr/bin/env bash
# Regenerate README palettes.png (300x200 capture, 2x nearest -> 600x400).
#
# Usage (from repo root or anywhere):
#   ./scripts/dev/capture_palettes_readme_images.sh

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
if [[ ! -f scripts/dev/capture_palettes_readme_images.lua ]]; then
  echo "Error: missing scripts/dev/capture_palettes_readme_images.lua" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/img/readme_images"

echo "==> Capturing palettes.png at 300x200 (2x -> 600x400) via LOVE"
love . --capture-palettes

echo "Done. PNG in $ROOT_DIR/img/readme_images/palettes.png"
