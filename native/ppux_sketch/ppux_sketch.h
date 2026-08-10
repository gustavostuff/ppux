#ifndef PPUX_SKETCH_H
#define PPUX_SKETCH_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
  PPUX_SKETCH_OK = 0,
  PPUX_SKETCH_ERR_NULL = 1,
  PPUX_SKETCH_ERR_DIMS = 2,
  PPUX_SKETCH_ERR_TOO_MANY_COLORS = 3,
  PPUX_SKETCH_ERR_TOO_MANY_UNIQUE = 4,
  PPUX_SKETCH_ERR_PALETTE = 5
};

typedef struct PpuxPoolEntry {
  int32_t x;
  int32_t y;
  int32_t solid_shade; /* -1 = none; else 0..3 */
  int32_t exact_solid; /* 0/1 */
} PpuxPoolEntry;

/* rgba: width*height*4 floats in LOVE getPixel order (r,g,b,a), each 0..1.
 * palette_rgb_12: 4*3 floats for NES slots 0..3, or NULL for brightness-only.
 * out_flat: caller-owned width*height bytes, values 0..3.
 */
int ppux_rgba_f32_to_indexed(
  const float *rgba,
  int w,
  int h,
  const float *palette_rgb_12,
  uint8_t *out_flat
);

/* Same as ppux_rgba_f32_to_indexed but LOVE ImageData rgba8 bytes (0..255). */
int ppux_rgba_u8_to_indexed(
  const uint8_t *rgba,
  int w,
  int h,
  const float *palette_rgb_12,
  uint8_t *out_flat
);

/* flat: 256x240 indexed 0..3 row-major.
 * out_pool: capacity 256.
 * out_nametable: 960 entries, 0-based pool indices.
 */
int ppux_pack_flat_tol0(
  const uint8_t *flat,
  int w,
  int h,
  PpuxPoolEntry *out_pool,
  int32_t *out_unique_count,
  uint16_t *out_nametable
);

const char *ppux_sketch_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* PPUX_SKETCH_H */
