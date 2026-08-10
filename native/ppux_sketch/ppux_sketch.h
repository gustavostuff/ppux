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
  PPUX_SKETCH_ERR_PALETTE = 5,
  PPUX_SKETCH_ERR_BOUNDS = 6
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
 * tolerance: 0 = exact match; 1..32 = greedy pixel-diff match (Lua packFromCanvas).
 */
int ppux_pack_flat(
  const uint8_t *flat,
  int w,
  int h,
  int tolerance,
  PpuxPoolEntry *out_pool,
  int32_t *out_unique_count,
  uint16_t *out_nametable
);

/* Convenience wrapper: ppux_pack_flat(..., 0, ...). */
int ppux_pack_flat_tol0(
  const uint8_t *flat,
  int w,
  int h,
  PpuxPoolEntry *out_pool,
  int32_t *out_unique_count,
  uint16_t *out_nametable
);

/* Copy n indexed bytes, clamping each to 0..3. */
int ppux_copy_flat(const uint8_t *src, uint8_t *dst, int n);

/* Blit src (src_w x src_h) into dst at (dx, dy). Clips to dst bounds. */
int ppux_blit_flat(
  const uint8_t *src,
  int src_w,
  int src_h,
  uint8_t *dst,
  int dst_w,
  int dst_h,
  int dx,
  int dy
);

/* Fill rect in flat with value 0..3 (clipped). */
int ppux_fill_flat_rect(
  uint8_t *flat,
  int w,
  int h,
  int x,
  int y,
  int rw,
  int rh,
  uint8_t value
);

/* Compose 256x240 from paint + pool sample points + nametable.
 * solid_shade[i] = -1 => sample 8x8 from paint at (pool_x, pool_y);
 * else use solid if paint tile still matches that shade, else sample paint.
 */
int ppux_compose_nametable(
  const uint8_t *paint,
  int w,
  int h,
  const int32_t *pool_x,
  const int32_t *pool_y,
  const int32_t *solid_shade,
  int pool_count,
  const uint16_t *nametable,
  uint8_t *out_flat
);

/* Average each nametable cell to RGB (960 * 3 doubles).
 * palette_rgb_48: 4 rows * 4 shades * rgb (row-major).
 * attr_row: 960 values 0..3 selecting palette row; NULL => row 0.
 */
int ppux_average_nametable_rgb(
  const uint8_t *paint,
  int w,
  int h,
  const int32_t *pool_x,
  const int32_t *pool_y,
  const int32_t *solid_shade,
  int pool_count,
  const uint16_t *nametable,
  const uint8_t *attr_row,
  const double *palette_rgb_48,
  double *out_rgb
);

/* Average each 8x8 of a flat canvas (no pack) to RGB. */
int ppux_average_flat_rgb(
  const uint8_t *flat,
  int w,
  int h,
  const uint8_t *attr_row,
  const double *palette_rgb_48,
  double *out_rgb
);

/* Flood fill. Mutates flat in place.
 * allow_mask: nullable length w*h; 0 = treat like blocked (visited, not painted).
 * out_indices: nullable capacity w*h of linear indices that changed.
 * out_count: number written to out_indices / pixels painted.
 */
int ppux_flood_fill(
  uint8_t *flat,
  int w,
  int h,
  int sx,
  int sy,
  uint8_t fill,
  const uint8_t *allow_mask,
  int32_t *out_indices,
  int32_t *out_count
);

/* Mark out_mask[i]=1 where flat[i]==shade; returns count via out_count. */
int ppux_build_shade_mask(
  const uint8_t *flat,
  int w,
  int h,
  uint8_t shade,
  uint8_t *out_mask,
  int32_t *out_count
);

/* Decode NES CHR tiles into grayscale rgba8 (0..255).
 * chr: tile_count * 16 bytes (1-based Lua banks are copied 0-based here).
 * tile_order: length cols*rows mapping grid pos -> tile index; NULL = identity.
 * out_rgba: (cols*8)*(rows*8)*4 bytes.
 */
int ppux_chr_tiles_to_rgba8(
  const uint8_t *chr,
  int tile_count,
  const int32_t *tile_order,
  int cols,
  int rows,
  uint8_t *out_rgba
);

const char *ppux_sketch_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* PPUX_SKETCH_H */
