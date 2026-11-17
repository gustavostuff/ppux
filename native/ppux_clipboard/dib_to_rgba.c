#include "ppux_clipboard.h"

#include <stdlib.h>
#include <string.h>

static uint16_t read_u16(const uint8_t *p) {
  return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t read_u32(const uint8_t *p) {
  return (uint32_t)p[0]
    | ((uint32_t)p[1] << 8)
    | ((uint32_t)p[2] << 16)
    | ((uint32_t)p[3] << 24);
}

static int32_t read_i32(const uint8_t *p) {
  return (int32_t)read_u32(p);
}

static int mask_shift(uint32_t mask) {
  int shift = 0;
  if (mask == 0) {
    return 0;
  }
  while ((mask & 1u) == 0u) {
    mask >>= 1;
    shift++;
  }
  return shift;
}

static int mask_bits(uint32_t mask) {
  int bits = 0;
  while (mask) {
    bits += (int)(mask & 1u);
    mask >>= 1;
  }
  return bits;
}

static uint8_t scale_channel(uint32_t value, int bits) {
  if (bits <= 0) {
    return 0;
  }
  if (bits >= 8) {
    return (uint8_t)(value & 0xFFu);
  }
  uint32_t maxv = (1u << bits) - 1u;
  if (maxv == 0) {
    return 0;
  }
  return (uint8_t)((value * 255u) / maxv);
}

int ppux_dib_to_rgba(
  const uint8_t *dib,
  size_t dib_size,
  uint8_t **out_rgba,
  int32_t *out_w,
  int32_t *out_h
) {
  if (out_rgba) {
    *out_rgba = NULL;
  }
  if (out_w) {
    *out_w = 0;
  }
  if (out_h) {
    *out_h = 0;
  }
  if (!dib || dib_size < 40 || !out_rgba || !out_w || !out_h) {
    return 1;
  }

  uint32_t bi_size = read_u32(dib + 0);
  if (bi_size < 40 || (size_t)bi_size > dib_size) {
    return 2;
  }

  int32_t width = read_i32(dib + 4);
  int32_t height_raw = read_i32(dib + 8);
  uint16_t planes = read_u16(dib + 12);
  uint16_t bit_count = read_u16(dib + 14);
  uint32_t compression = read_u32(dib + 16);
  uint32_t clr_used = read_u32(dib + 32);

  if (planes != 1 || width <= 0 || width > 16384) {
    return 3;
  }
  int top_down = height_raw < 0;
  int32_t height = height_raw < 0 ? -height_raw : height_raw;
  if (height <= 0 || height > 16384) {
    return 3;
  }
  if (bit_count != 24 && bit_count != 32) {
    return 4;
  }
  /* BI_RGB = 0, BI_BITFIELDS = 3 */
  if (compression != 0 && compression != 3) {
    return 5;
  }

  uint32_t red_mask = 0;
  uint32_t green_mask = 0;
  uint32_t blue_mask = 0;
  uint32_t alpha_mask = 0;
  size_t pixel_offset = (size_t)bi_size;

  if (compression == 3) {
    if (bi_size >= 56) {
      /* BITMAPV4HEADER / V5 store the masks inside the header. */
      if (dib_size < 56) {
        return 6;
      }
      red_mask = read_u32(dib + 40);
      green_mask = read_u32(dib + 44);
      blue_mask = read_u32(dib + 48);
      if (bi_size >= 60) {
        alpha_mask = read_u32(dib + 52);
      }
    } else {
      /* BITMAPINFOHEADER followed by three DWORD masks. */
      if (dib_size < 52) {
        return 6;
      }
      red_mask = read_u32(dib + 40);
      green_mask = read_u32(dib + 44);
      blue_mask = read_u32(dib + 48);
      pixel_offset = 52;
    }
  } else if (bit_count == 24) {
    blue_mask = 0x000000FFu;
    green_mask = 0x0000FF00u;
    red_mask = 0x00FF0000u;
  } else {
    blue_mask = 0x000000FFu;
    green_mask = 0x0000FF00u;
    red_mask = 0x00FF0000u;
  }

  if (compression != 3 && clr_used > 0) {
    pixel_offset += (size_t)clr_used * 4u;
  } else if (compression == 3 && bi_size >= 56 && clr_used > 0) {
    pixel_offset += (size_t)clr_used * 4u;
  }

  if (red_mask == 0 || green_mask == 0 || blue_mask == 0) {
    return 8;
  }

  size_t stride = (((size_t)width * (size_t)bit_count + 31u) / 32u) * 4u;
  if (pixel_offset > dib_size || stride * (size_t)height > dib_size - pixel_offset) {
    return 7;
  }

  size_t pixel_count = (size_t)width * (size_t)height;
  uint8_t *rgba = (uint8_t *)malloc(pixel_count * 4u);
  if (!rgba) {
    return 9;
  }

  int r_shift = mask_shift(red_mask);
  int g_shift = mask_shift(green_mask);
  int b_shift = mask_shift(blue_mask);
  int a_shift = mask_shift(alpha_mask);
  int r_bits = mask_bits(red_mask);
  int g_bits = mask_bits(green_mask);
  int b_bits = mask_bits(blue_mask);
  int a_bits = mask_bits(alpha_mask);
  size_t bpp = (size_t)bit_count / 8u;

  /* 32-bit BI_RGB leaves the high byte unused (often 0). Treat it as
   * alpha only when some pixel actually stores a non-zero value. */
  int use_rgb32_alpha = 0;
  if (compression == 0 && bit_count == 32) {
    for (int32_t y = 0; y < height && !use_rgb32_alpha; y++) {
      const uint8_t *row = dib + pixel_offset + (size_t)y * stride;
      for (int32_t x = 0; x < width; x++) {
        if (row[(size_t)x * 4u + 3u] != 0) {
          use_rgb32_alpha = 1;
          break;
        }
      }
    }
  }

  for (int32_t y = 0; y < height; y++) {
    int32_t src_y = top_down ? y : (height - 1 - y);
    const uint8_t *row = dib + pixel_offset + (size_t)src_y * stride;
    for (int32_t x = 0; x < width; x++) {
      const uint8_t *px = row + (size_t)x * bpp;
      uint32_t pix;
      if (bit_count == 24) {
        pix = (uint32_t)px[0] | ((uint32_t)px[1] << 8) | ((uint32_t)px[2] << 16);
      } else {
        pix = read_u32(px);
      }
      uint8_t r = scale_channel((pix & red_mask) >> r_shift, r_bits);
      uint8_t g = scale_channel((pix & green_mask) >> g_shift, g_bits);
      uint8_t b = scale_channel((pix & blue_mask) >> b_shift, b_bits);
      uint8_t a = 255;
      if (alpha_mask) {
        a = scale_channel((pix & alpha_mask) >> a_shift, a_bits);
      } else if (use_rgb32_alpha) {
        a = (uint8_t)((pix >> 24) & 0xFFu);
      }
      size_t o = ((size_t)y * (size_t)width + (size_t)x) * 4u;
      rgba[o + 0] = r;
      rgba[o + 1] = g;
      rgba[o + 2] = b;
      rgba[o + 3] = a;
    }
  }

  *out_rgba = rgba;
  *out_w = width;
  *out_h = height;
  return 0;
}
