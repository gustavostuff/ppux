#!/usr/bin/env python3
"""
Sample a horizontal hue-ramp PNG and emit HSL hues [0,1) for ColorPickerMatrix columns.

Matches ppux rgbToHsl semantics (user_interface/color_picker_matrix.lua).

Usage:
  python3 tools/extract_hue_ramp.py [path/to/ramp.png] [--columns 8] [--lua-out path.lua]
  python3 tools/extract_hue_ramp.py ramp.png --full-row-json all_pixels.json

RGB values are read from the PNG pixels (after flattening alpha onto white), not guessed.
Default input: assets/hue_ramp.png (use a wide, native-resolution strip for smooth ramps).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def rgb_to_hsl(r: float, g: float, b: float) -> tuple[float, float, float]:
    """r,g,b in [0,1]. Returns h,s,l with h in [0,1), same branches as Lua rgbToHsl."""
    mx = max(r, g, b)
    mn = min(r, g, b)
    d = mx - mn
    l = (mx + mn) * 0.5
    if d <= 1e-10:
        return 0.0, 0.0, l
    s = (d / (2.0 - mx - mn)) if (l > 0.5) else (d / (mx + mn))
    if mx == mn:
        h = 0.0
    elif mx == r:
        h = ((g - b) / d + (6.0 if g < b else 0.0)) / 6.0
    elif mx == g:
        h = ((b - r) / d + 2.0) / 6.0
    else:
        h = ((r - g) / d + 4.0) / 6.0
    h = h % 1.0
    return h, s, l


def load_rgba(path: Path):
    try:
        from PIL import Image
    except ImportError as e:
        print("Requires Pillow: pip install Pillow", file=sys.stderr)
        raise SystemExit(1) from e
    im = Image.open(path).convert("RGBA")
    return im


def _flatten_rgba_on_white(r: int, g: int, b: int, a: int) -> tuple[float, float, float]:
    aa = a / 255.0
    rf = (r / 255.0) * aa + (1.0 - aa)
    gf = (g / 255.0) * aa + (1.0 - aa)
    bf = (b / 255.0) * aa + (1.0 - aa)
    return rf, gf, bf


def rgb01_to_bytes(rf: float, gf: float, bf: float) -> tuple[int, int, int]:
    r = int(max(0, min(255, round(rf * 255))))
    g = int(max(0, min(255, round(gf * 255))))
    b = int(max(0, min(255, round(bf * 255))))
    return r, g, b


def sample_row_rgbs(im, y: int | None, n_columns: int) -> list[tuple[int, float, float, float]]:
    """Each stop: (pixel_x, r, g, b) in [0,1] after flattening RGBA onto white."""
    w, h = im.size
    if w < 1 or h < 1:
        raise ValueError(f"image too small: {w}x{h}")
    row = h // 2 if y is None else max(0, min(h - 1, y))
    px = im.load()
    out: list[tuple[int, float, float, float]] = []
    for i in range(n_columns):
        x = int((i + 0.5) * w / n_columns)
        x = max(0, min(w - 1, x))
        r, g, b, a = px[x, row]
        rf, gf, bf = _flatten_rgba_on_white(r, g, b, a)
        out.append((x, rf, gf, bf))
    return out


def sample_full_row_rgbs(im, y: int | None) -> list[tuple[int, float, float, float]]:
    """One sample per column x=0..w-1 (exact pixels along the row)."""
    w, h = im.size
    if w < 1 or h < 1:
        raise ValueError(f"image too small: {w}x{h}")
    row = h // 2 if y is None else max(0, min(h - 1, y))
    px = im.load()
    out: list[tuple[int, float, float, float]] = []
    for x in range(w):
        r, g, b, a = px[x, row]
        rf, gf, bf = _flatten_rgba_on_white(r, g, b, a)
        out.append((x, rf, gf, bf))
    return out


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "image",
        nargs="?",
        default=str(root / "assets" / "hue_ramp.png"),
        help="Horizontal hue ramp PNG",
    )
    ap.add_argument("--columns", type=int, default=8, help="Picker matrix columns (default 8)")
    ap.add_argument("--row", type=int, default=None, help="Sample row (default: image height // 2)")
    ap.add_argument("--json-out", type=str, default=None, help="Write samples JSON here")
    ap.add_argument("--lua-out", type=str, default=None, help="Write Lua hue table module here")
    ap.add_argument(
        "--full-row-json",
        type=str,
        default=None,
        help="Write JSON with one RGB sample per image column (width pixels)",
    )
    args = ap.parse_args()

    path = Path(args.image)
    if not path.is_file():
        print(f"Missing image: {path}", file=sys.stderr)
        raise SystemExit(2)

    im = load_rgba(path)
    w, h = im.size
    rgbs = sample_row_rgbs(im, args.row, args.columns)
    rows: list[dict] = []
    hues: list[float] = []
    for i, (pixel_x, rf, gf, bf) in enumerate(rgbs):
        hh, ss, ll = rgb_to_hsl(rf, gf, bf)
        hues.append(round(hh, 10))
        r8, g8, b8 = rgb01_to_bytes(rf, gf, bf)
        rows.append(
            {
                "column": i + 1,
                "pixel_x": pixel_x,
                "rgb_01": [round(rf, 6), round(gf, 6), round(bf, 6)],
                "rgb_255": [r8, g8, b8],
                "hex": f"#{r8:02x}{g8:02x}{b8:02x}",
                "hsl_h": hh,
                "hsl_s": ss,
                "hsl_l": ll,
            }
        )

    payload = {
        "source_image": str(path.resolve()),
        "size": [w, h],
        "sample_row": h // 2 if args.row is None else int(args.row),
        "columns": args.columns,
        "samples": rows,
    }

    print(json.dumps(payload, indent=2))

    if args.json_out:
        outp = Path(args.json_out)
        outp.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        print(f"Wrote {outp}", file=sys.stderr)

    if args.full_row_json:
        full = sample_full_row_rgbs(im, args.row)
        full_rows: list[dict] = []
        for pixel_x, rf, gf, bf in full:
            hh, ss, ll = rgb_to_hsl(rf, gf, bf)
            r8, g8, b8 = rgb01_to_bytes(rf, gf, bf)
            full_rows.append(
                {
                    "pixel_x": pixel_x,
                    "rgb_01": [round(rf, 6), round(gf, 6), round(bf, 6)],
                    "rgb_255": [r8, g8, b8],
                    "hex": f"#{r8:02x}{g8:02x}{b8:02x}",
                    "hsl_h": hh,
                    "hsl_s": ss,
                    "hsl_l": ll,
                }
            )
        full_payload = {
            "source_image": str(path.resolve()),
            "size": [w, h],
            "sample_row": h // 2 if args.row is None else int(args.row),
            "pixels": full_rows,
        }
        outp = Path(args.full_row_json)
        outp.write_text(json.dumps(full_payload, indent=2), encoding="utf-8")
        print(f"Wrote {outp} ({len(full_rows)} samples)", file=sys.stderr)

    if args.lua_out:
        rel = path.resolve().relative_to(root) if str(path.resolve()).startswith(str(root)) else path.name
        lines = [
            "-- Generated by tools/extract_hue_ramp.py — do not edit by hand.",
            f"-- Source: {rel} ({w}x{h}), {args.columns} stops along sample row.",
            "return {",
        ]
        for i, hval in enumerate(hues):
            comma = "," if i < len(hues) - 1 else ""
            x, rf, gf, bf = rgbs[i]
            r8, g8, b8 = rgb01_to_bytes(rf, gf, bf)
            hx = f"#{r8:02x}{g8:02x}{b8:02x}"
            lines.append(f"  {hval}{comma} -- col {i + 1} x={x} {hx} rgb({r8},{g8},{b8})")
        lines.append("}")
        Path(args.lua_out).write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"Wrote {args.lua_out}", file=sys.stderr)


if __name__ == "__main__":
    main()
