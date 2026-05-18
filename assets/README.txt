hue_ramp.png — horizontal hue strip for the color picker matrix.

Replace this file with your own ramp exported at full pixel resolution, then regenerate:

  python3 tools/extract_hue_ramp.py assets/hue_ramp.png --lua-out user_interface/hue_ramp_matrix_columns.lua

Optional: dump every column’s RGB to JSON (image width samples):

  python3 tools/extract_hue_ramp.py assets/hue_ramp.png --full-row-json /tmp/hue_ramp_all_pixels.json

If the PNG is only a few pixels wide, the picker still works but you only get that many distinct underlying colors.
