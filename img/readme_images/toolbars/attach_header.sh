#!/bin/bash

# Check for correct number of arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <directory> <path_to_header_image>"
    echo "Example: $0 ./images ./header.png"
    exit 1
fi

DIR="$1"
HEADER="$2"

# Validate that the directory exists
if [ ! -d "$DIR" ]; then
    echo "Error: Directory '$DIR' does not exist."
    exit 1
fi

# Validate that the header image exists
if [ ! -f "$HEADER" ]; then
    echo "Error: Header image '$HEADER' does not exist."
    exit 1
fi

# Create an output directory
OUT_DIR="$DIR/with_header"
mkdir -p "$OUT_DIR"

# Enable nullglob and nocaseglob for image extensions
shopt -s nullglob nocaseglob

count=0

# Get absolute paths to prevent processing the header if it's in the same folder
HEADER_ABS=$(readlink -f "$HEADER")

for img in "$DIR"/*.{png,jpg,jpeg,webp,gif,bmp,tiff}; do
    IMG_ABS=$(readlink -f "$img")
    
    # Skip the header image itself
    if [ "$IMG_ABS" == "$HEADER_ABS" ]; then
        continue
    fi

    # Extract the filename without the extension, so we can force the output to be .png
    filename=$(basename -- "$img")
    name="${filename%.*}"
    out_file="$OUT_DIR/$name.png"
    
    echo "Processing: $filename -> $name.png"
    
    # -filter_complex breakdown:
    # format=rgba    -> FORCES the original image to have an alpha channel before any padding occurs.
    # pad=...        -> Expands canvas to 200%. Because the image now has an alpha channel, black@0 renders as true transparency.
    # overlay=...    -> Places the header at top-left. format=rgb forces RGB processing, preventing color compression (noise).
    ffmpeg -v error -y -i "$img" -i "$HEADER" \
           -filter_complex "[0:v]format=rgba,pad=iw:ih*2:0:ih:color=black@0[bg];[bg][1:v]overlay=0:0:format=rgb" \
           -c:v png -pix_fmt rgba \
           "$out_file"
           
    ((count++))
done

echo "----------------------------------------"
if [ "$count" -eq 0 ]; then
    echo "No matching images found in '$DIR'."
else
    echo "Success! Attached header to $count image(s)."
    echo "Output saved to: $OUT_DIR"
fi
