#!/bin/bash

# Check for correct number of arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <directory> <scale_factor>"
    echo "Example: $0 ./images 0.5  (shrinks images to 50% and saves to ./images/0.5x)"
    exit 1
fi

DIR="$1"
FACTOR="$2"

# Validate that the directory exists
if [ ! -d "$DIR" ]; then
    echo "Error: Directory '$DIR' does not exist."
    exit 1
fi

# Validate that the factor is a valid positive number (integer or decimal)
if ! [[ "$FACTOR" =~ ^[0-9]*\.?[0-9]+$ ]]; then
    echo "Error: The factor must be a valid number (e.g., 0.5, 2)."
    exit 1
fi

# Ensure the factor is greater than 0
if awk "BEGIN {exit !($FACTOR <= 0)}"; then
    echo "Error: The factor must be greater than 0."
    exit 1
fi

# Create the dynamic output directory based on the scale factor (e.g., "0.5x")
OUT_DIR="$DIR/${FACTOR}x"
mkdir -p "$OUT_DIR"

# Enable nullglob (prevents loop from running if no files match) 
# and nocaseglob (matches .PNG and .png equally)
shopt -s nullglob nocaseglob

count=0

# Loop through common image extensions
for img in "$DIR"/*.{png,jpg,jpeg,webp,gif,bmp,tiff}; do
    filename=$(basename -- "$img")
    
    echo "Processing: $filename"
    
    # -v error: Keeps console output clean (only shows errors)
    # -y: Overwrites output files without asking
    # -vf scale=...: Multiplies width (iw) and height (ih) by the decimal factor. 
    #                round() ensures we don't pass fractional pixels to the encoder.
    # flags=neighbor: Forces nearest-neighbor interpolation to prevent fuzziness.
    ffmpeg -v error -y -i "$img" \
           -vf "scale=round(iw*$FACTOR):round(ih*$FACTOR):flags=neighbor" \
           "$OUT_DIR/$filename"
           
    ((count++))
done

echo "----------------------------------------"
if [ "$count" -eq 0 ]; then
    echo "No images found in '$DIR'."
else
    echo "Success! Scaled $count image(s) by a factor of $FACTOR."
    echo "Output saved to: $OUT_DIR"
fi
