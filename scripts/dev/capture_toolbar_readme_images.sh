#!/usr/bin/env bash
# This was AI generated!
#
# Regenerate README toolbar PNGs (1x capture -> attach header -> 2x).
#
# Capture remaps disabled icon gray #6d6d6d -> #b6b6b6 so buttons look enabled.
#
# Usage (from repo root or anywhere):
#   ./scripts/dev/capture_toolbar_readme_images.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v love >/dev/null 2>&1; then
  echo "Error: 'love' command not found." >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: 'ffmpeg' command not found (needed by attach_header.sh / scale_images.sh)." >&2
  exit 1
fi
if [[ ! -f scripts/dev/capture_toolbar_readme_images.lua ]]; then
  echo "Error: missing scripts/dev/capture_toolbar_readme_images.lua" >&2
  exit 1
fi

TOOLBARS_DIR="$ROOT_DIR/img/readme_images/toolbars"
mkdir -p "$TOOLBARS_DIR"

echo "==> Capturing toolbars at 1x via LOVE"
love . --capture-toolbars

echo "==> attach_header.sh"
(
  cd "$TOOLBARS_DIR"
  rm -rf with_header
  ./attach_header.sh . ./header.png
)

echo "==> scale_images.sh (2x)"
(
  cd "$TOOLBARS_DIR"
  ./scale_images.sh ./with_header 2
  rm -rf 2x
  mv with_header/2x ./2x
  rm -rf with_header
)

echo "Done. 1x PNGs in $TOOLBARS_DIR ; 2x PNGs in $TOOLBARS_DIR/2x"
