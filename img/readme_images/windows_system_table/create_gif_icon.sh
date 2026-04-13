#!/bin/bash

error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# 1. Dependency Check
for cmd in ffmpeg ffprobe; do
    command -v "$cmd" >/dev/null 2>&1 || error_exit "This script requires '$cmd'."
done

# 2. Argument Validation
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <source_png> <num_frames> <frame_duration_ms> [scale]"
    echo "Example: $0 sheet.png 8 400 4"
    exit 1
fi

SOURCE=$1
FRAMES=$2
DELAY_MS=$3
SCALE=${4:-1}

[[ -f "$SOURCE" ]] || error_exit "File '$SOURCE' not found."

# 3. Get Dimensions
TOTAL_W=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$SOURCE")
HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$SOURCE")
FRAME_W=$(( TOTAL_W / FRAMES ))

OUTPUT="${SOURCE%.*}.gif"

echo "Processing: $SOURCE"
echo "Frame Size: ${FRAME_W}x${HEIGHT} -> $((FRAME_W * SCALE))x$((HEIGHT * SCALE))"
echo "Duration: ${DELAY_MS}ms per frame ($((1000 / DELAY_MS)) FPS)"

# 4. The FFmpeg Command
# -loop 1 + -framerate: Sets the speed of the source before any filters act on it.
# trim=end_frame: This is the "EOF" signal that prevents the script from hanging.
ffmpeg -y -v warning \
  -loop 1 -framerate 1000/"$DELAY_MS" -i "$SOURCE" \
  -filter_complex \
  "[0:v]crop=$FRAME_W:$HEIGHT:n*$FRAME_W:0, \
   scale=iw*$SCALE:ih*$SCALE:flags=neighbor, \
   trim=end_frame=$FRAMES, \
   split[s0][s1]; \
   [s0]palettegen[p]; \
   [s1][p]paletteuse" \
  -loop 0 "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "Success! Created: $OUTPUT"
else
    error_exit "FFmpeg encountered an error."
fi
