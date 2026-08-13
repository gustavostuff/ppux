#!/usr/bin/env bash
# Regenerate README window-link example PNGs (300x200 capture, 2x nearest -> 600x400).
#
# Usage (from repo root or anywhere):
#   ./scripts/dev/capture_source_links_readme_images.sh

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
if [[ ! -f scripts/dev/capture_source_links_readme_images.lua ]]; then
  echo "Error: missing scripts/dev/capture_source_links_readme_images.lua" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/img/readme_images"

echo "==> Capturing source-link examples at 300x200 (2x -> 600x400) via LOVE"
love . --capture-source-links

echo "Done. PNGs in $ROOT_DIR/img/readme_images/source_links_example_{1,2,3,4}.png"
