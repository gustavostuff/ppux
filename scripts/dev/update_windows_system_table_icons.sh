#!/usr/bin/env bash
# Scale taskbar icons from img/windows_icons into the README Windows system table.
# Static icons -> 3x nearest-neighbor PNGs.
# Names containing "animated" are 1-row 8-frame sheets -> 3x looping GIFs at 0.1s/frame.
#
# Usage (from repo root or anywhere):
#   ./scripts/dev/update_windows_system_table_icons.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

SRC_DIR="$ROOT_DIR/img/windows_icons"
DST_DIR="$ROOT_DIR/img/readme_images/windows_system_table"
SCALE=3
ANIM_FRAMES=8
ANIM_DELAY_MS=100

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: 'ffmpeg' command not found." >&2
  exit 1
fi
if ! command -v ffprobe >/dev/null 2>&1; then
  echo "Error: 'ffprobe' command not found." >&2
  exit 1
fi
if [[ ! -d "$SRC_DIR" ]]; then
  echo "Error: missing $SRC_DIR" >&2
  exit 1
fi

mkdir -p "$DST_DIR"

png_dim() {
  ffprobe -v error -select_streams v:0 -show_entries stream="$1" -of default=noprint_wrappers=1:nokey=1 "$2"
}

scale_static() {
  local src=$1
  local dest=$2
  ffmpeg -v error -y -i "$src" \
    -vf "scale=iw*${SCALE}:ih*${SCALE}:flags=neighbor" \
    -pix_fmt rgba \
    "$dest"
}

pack_animated_gif() {
  local src=$1
  local dest=$2
  local total_w height frame_w
  total_w=$(png_dim width "$src")
  height=$(png_dim height "$src")
  if (( total_w % ANIM_FRAMES != 0 )); then
    echo "Error: $(basename "$src") width ${total_w} is not divisible by ${ANIM_FRAMES}." >&2
    exit 1
  fi
  frame_w=$((total_w / ANIM_FRAMES))
  echo "  sheet ${total_w}x${height} -> ${ANIM_FRAMES} frames of ${frame_w}x${height}, ${SCALE}x GIF"
  ffmpeg -y -v warning \
    -loop 1 -framerate "1000/${ANIM_DELAY_MS}" -i "$src" \
    -filter_complex \
    "[0:v]crop=${frame_w}:${height}:n*${frame_w}:0,scale=iw*${SCALE}:ih*${SCALE}:flags=neighbor,trim=end_frame=${ANIM_FRAMES},split[s0][s1];[s0]palettegen=reserve_transparent=1:stats_mode=single[p];[s1][p]paletteuse=dither=none:alpha_threshold=128" \
    -loop 0 \
    "$dest"
}

shopt -s nullglob
count=0
for src in "$SRC_DIR"/*.png; do
  base=$(basename "$src")
  stem=${base%.png}
  echo "Processing: $base"
  if [[ "$stem" == *animated* ]]; then
    dest="$DST_DIR/${stem}.gif"
    pack_animated_gif "$src" "$dest"
    rm -f "$DST_DIR/${stem}.png"
  else
    dest="$DST_DIR/${stem}.png"
    scale_static "$src" "$dest"
    # README historically used this name for the sketch-canvas row.
    if [[ "$stem" == "icon_sketch_canvas_window" ]]; then
      cp -f "$dest" "$DST_DIR/sketch_canvas_window.png"
    fi
  fi
  count=$((count + 1))
done

if (( count == 0 )); then
  echo "Error: no PNGs in $SRC_DIR" >&2
  exit 1
fi

echo "Done. ${count} icon(s) written to $DST_DIR (${SCALE}x)."
