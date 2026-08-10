#include "ppux_sketch.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PPUX_GRID_COLS 32
#define PPUX_GRID_ROWS 30
#define PPUX_CELL 8
#define PPUX_MAX_UNIQUE 256
#define PPUX_NT_CELLS (PPUX_GRID_COLS * PPUX_GRID_ROWS)
#define PPUX_EXPECT_W (PPUX_GRID_COLS * PPUX_CELL)
#define PPUX_EXPECT_H (PPUX_GRID_ROWS * PPUX_CELL)
#define PPUX_MAX_COLORS 64

static char g_last_error[256] = "";

static void set_error(const char *msg) {
  if (!msg) {
    g_last_error[0] = '\0';
    return;
  }
  snprintf(g_last_error, sizeof(g_last_error), "%s", msg);
}

const char *ppux_sketch_last_error(void) {
  return g_last_error;
}

static int rgb_key(double r, double g, double b, int *out_r8, int *out_g8, int *out_b8) {
  if (r < 0.0) r = 0.0;
  if (g < 0.0) g = 0.0;
  if (b < 0.0) b = 0.0;
  int r8 = (int)floor(r * 255.0 + 0.5);
  int g8 = (int)floor(g * 255.0 + 0.5);
  int b8 = (int)floor(b * 255.0 + 0.5);
  if (r8 < 0) r8 = 0;
  if (g8 < 0) g8 = 0;
  if (b8 < 0) b8 = 0;
  if (r8 > 255) r8 = 255;
  if (g8 > 255) g8 = 255;
  if (b8 > 255) b8 = 255;
  if (out_r8) *out_r8 = r8;
  if (out_g8) *out_g8 = g8;
  if (out_b8) *out_b8 = b8;
  return (r8 << 16) | (g8 << 8) | b8;
}

/* Match Lua: 0.299*r + 0.587*g + 0.114*b with double math. */
static double luminance(double r, double g, double b) {
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

/* Lua table.sort tie-break uses string keys from string.format("%d_%d_%d", ...).
 * Lexicographic strcmp is NOT the same as numeric (r,g,b) order
 * (e.g. "139_0_0" < "75_0_0" because '1' < '7'). */
static int cmp_rgb_key_string(int r1, int g1, int b1, int r2, int g2, int b2) {
  char ka[32];
  char kb[32];
  snprintf(ka, sizeof(ka), "%d_%d_%d", r1, g1, b1);
  snprintf(kb, sizeof(kb), "%d_%d_%d", r2, g2, b2);
  return strcmp(ka, kb);
}

typedef struct {
  int key;
  double lum;
  int r8, g8, b8;
} ColorEntry;

static int cmp_color_entry(const void *a, const void *b) {
  const ColorEntry *ea = (const ColorEntry *)a;
  const ColorEntry *eb = (const ColorEntry *)b;
  if (ea->lum < eb->lum) return -1;
  if (ea->lum > eb->lum) return 1;
  return cmp_rgb_key_string(ea->r8, ea->g8, ea->b8, eb->r8, eb->g8, eb->b8);
}

static int find_color(const ColorEntry *entries, int n, int key) {
  int i;
  for (i = 0; i < n; i++) {
    if (entries[i].key == key) return i;
  }
  return -1;
}

static double color_dist2_entry(const ColorEntry *e, const float *palette_rgb_12, int slot) {
  double cr = (double)e->r8 / 255.0;
  double cg = (double)e->g8 / 255.0;
  double cb = (double)e->b8 / 255.0;
  double pr = (double)palette_rgb_12[slot * 3 + 0];
  double pg = (double)palette_rgb_12[slot * 3 + 1];
  double pb = (double)palette_rgb_12[slot * 3 + 2];
  double dr = cr - pr, dg = cg - pg, db = cb - pb;
  return dr * dr + dg * dg + db * db;
}

typedef struct {
  const ColorEntry *entries;
  int unique;
  const float *palette_rgb_12;
  const int *slots;
  int nslots;
  int *used_slot;
  int *choice; /* color index -> slot index in slots[] */
  int *best_choice;
  double best_cost;
} AssignCtx;

static void assign_search(AssignCtx *ctx, int depth, double cost) {
  int s;
  if (cost >= ctx->best_cost) {
    return;
  }
  if (depth == ctx->unique) {
    int i;
    ctx->best_cost = cost;
    for (i = 0; i < ctx->unique; i++) {
      ctx->best_choice[i] = ctx->choice[i];
    }
    return;
  }
  for (s = 0; s < ctx->nslots; s++) {
    if (ctx->used_slot[s]) continue;
    ctx->used_slot[s] = 1;
    ctx->choice[depth] = s;
    assign_search(
      ctx,
      depth + 1,
      cost + color_dist2_entry(&ctx->entries[depth], ctx->palette_rgb_12, ctx->slots[s])
    );
    ctx->used_slot[s] = 0;
  }
}

static int rgba_to_indexed_impl(
  int w,
  int h,
  const float *palette_rgb_12,
  uint8_t *out_flat,
  void (*sample)(const void *ctx, int x, int y, double out_rgba[4]),
  const void *ctx
) {
  ColorEntry entries[PPUX_MAX_COLORS];
  int unique = 0;
  int has_transparency = 0;
  int x, y, i;
  int index_of_entry[PPUX_MAX_COLORS];

  set_error("");
  if (!out_flat || !sample || w <= 0 || h <= 0) {
    set_error("null args or bad size");
    return PPUX_SKETCH_ERR_NULL;
  }

  for (y = 0; y < h; y++) {
    for (x = 0; x < w; x++) {
      double rgba[4];
      int r8, g8, b8, key;
      sample(ctx, x, y, rgba);
      /* Match Lua: unique colors only when a > 0; transparency when a == 0. */
      if (!(rgba[3] > 0.0)) {
        if (rgba[3] == 0.0) {
          has_transparency = 1;
        }
        continue;
      }
      key = rgb_key(rgba[0], rgba[1], rgba[2], &r8, &g8, &b8);
      if (find_color(entries, unique, key) >= 0) continue;
      if (unique >= PPUX_MAX_COLORS) {
        set_error("too many unique colors");
        return PPUX_SKETCH_ERR_TOO_MANY_COLORS;
      }
      entries[unique].key = key;
      entries[unique].lum = luminance(rgba[0], rgba[1], rgba[2]);
      entries[unique].r8 = r8;
      entries[unique].g8 = g8;
      entries[unique].b8 = b8;
      unique++;
    }
  }

  if (unique > 4) {
    set_error("image has more than 4 colors");
    return PPUX_SKETCH_ERR_TOO_MANY_COLORS;
  }

  /* Brightness ranks when no palette (Lua convertToIndexedByBrightness). */
  qsort(entries, (size_t)unique, sizeof(ColorEntry), cmp_color_entry);
  for (i = 0; i < unique; i++) {
    int rank = i;
    if (rank > 3) rank = 3;
    index_of_entry[i] = rank;
  }

  if (palette_rgb_12) {
    int slots[4];
    int nslots;
    int used_slot[4];
    int choice[4];
    int best_choice[4];
    AssignCtx actx;
    if (has_transparency) {
      nslots = 3;
      slots[0] = 1;
      slots[1] = 2;
      slots[2] = 3;
    } else {
      nslots = 4;
      slots[0] = 0;
      slots[1] = 1;
      slots[2] = 2;
      slots[3] = 3;
    }
    if (unique > nslots) {
      set_error("image has more than 4 colors");
      return PPUX_SKETCH_ERR_TOO_MANY_COLORS;
    }
    for (i = 0; i < 4; i++) {
      used_slot[i] = 0;
      choice[i] = -1;
      best_choice[i] = -1;
    }
    actx.entries = entries;
    actx.unique = unique;
    actx.palette_rgb_12 = palette_rgb_12;
    actx.slots = slots;
    actx.nslots = nslots;
    actx.used_slot = used_slot;
    actx.choice = choice;
    actx.best_choice = best_choice;
    actx.best_cost = 1e300;
    assign_search(&actx, 0, 0.0);
    for (i = 0; i < unique; i++) {
      int si = best_choice[i];
      index_of_entry[i] = (si >= 0) ? slots[si] : 0;
    }
  }

  for (y = 0; y < h; y++) {
    for (x = 0; x < w; x++) {
      double rgba[4];
      int idx = 0;
      size_t out_i = (size_t)(y * w + x);
      sample(ctx, x, y, rgba);
      if (rgba[3] == 0.0) {
        out_flat[out_i] = 0;
        continue;
      }
      {
        int key = rgb_key(rgba[0], rgba[1], rgba[2], NULL, NULL, NULL);
        int ei = find_color(entries, unique, key);
        if (ei >= 0) {
          idx = index_of_entry[ei];
        }
      }
      if (idx < 0) idx = 0;
      if (idx > 3) idx = 3;
      out_flat[out_i] = (uint8_t)idx;
    }
  }

  return PPUX_SKETCH_OK;
}

typedef struct {
  const float *rgba;
  int w;
} F32Ctx;

typedef struct {
  const uint8_t *rgba;
  int w;
} U8Ctx;

static void sample_f32_ctx(const void *ctx, int x, int y, double out_rgba[4]) {
  const F32Ctx *c = (const F32Ctx *)ctx;
  const float *px = c->rgba + ((size_t)(y * c->w + x) * 4);
  out_rgba[0] = (double)px[0];
  out_rgba[1] = (double)px[1];
  out_rgba[2] = (double)px[2];
  out_rgba[3] = (double)px[3];
}

static void sample_u8_ctx(const void *ctx, int x, int y, double out_rgba[4]) {
  const U8Ctx *c = (const U8Ctx *)ctx;
  const uint8_t *px = c->rgba + ((size_t)(y * c->w + x) * 4);
  /* Match LOVE getPixel: byte/255 as double (not float). */
  out_rgba[0] = (double)px[0] / 255.0;
  out_rgba[1] = (double)px[1] / 255.0;
  out_rgba[2] = (double)px[2] / 255.0;
  out_rgba[3] = (double)px[3] / 255.0;
}

int ppux_rgba_f32_to_indexed(
  const float *rgba,
  int w,
  int h,
  const float *palette_rgb_12,
  uint8_t *out_flat
) {
  F32Ctx ctx;
  if (!rgba) {
    set_error("null rgba");
    return PPUX_SKETCH_ERR_NULL;
  }
  ctx.rgba = rgba;
  ctx.w = w;
  return rgba_to_indexed_impl(w, h, palette_rgb_12, out_flat, sample_f32_ctx, &ctx);
}

int ppux_rgba_u8_to_indexed(
  const uint8_t *rgba,
  int w,
  int h,
  const float *palette_rgb_12,
  uint8_t *out_flat
) {
  U8Ctx ctx;
  if (!rgba) {
    set_error("null rgba");
    return PPUX_SKETCH_ERR_NULL;
  }
  ctx.rgba = rgba;
  ctx.w = w;
  return rgba_to_indexed_impl(w, h, palette_rgb_12, out_flat, sample_u8_ctx, &ctx);
}

static void extract_tile(
  const uint8_t *flat,
  int w,
  int ox,
  int oy,
  uint8_t out[64]
) {
  int py, px, i = 0;
  for (py = 0; py < PPUX_CELL; py++) {
    int row = (oy + py) * w;
    for (px = 0; px < PPUX_CELL; px++) {
      out[i++] = flat[row + ox + px];
    }
  }
}

static int solid_diff_count(const uint8_t pixels[64], int shade, int threshold) {
  int i, differences = 0;
  for (i = 0; i < 64; i++) {
    if (pixels[i] != (uint8_t)shade) {
      differences++;
      if (differences > threshold) return differences;
    }
  }
  return differences;
}

static int canonical_solid_shade(const uint8_t pixels[64]) {
  int shade;
  int best_shade = -1;
  int best_diff = 999;
  for (shade = 0; shade <= 3; shade++) {
    int diff = solid_diff_count(pixels, shade, 0);
    if (diff <= 0 && diff < best_diff) {
      best_shade = shade;
      best_diff = diff;
    }
  }
  return best_shade;
}

/* 16-byte exact key (same packing as Lua patternExactKey). */
static void pattern_exact_key(const uint8_t pixels[64], uint8_t key[16]) {
  int i, k = 0;
  for (i = 0; i < 64; i += 4) {
    unsigned a = pixels[i] & 3;
    unsigned b = pixels[i + 1] & 3;
    unsigned c = pixels[i + 2] & 3;
    unsigned d = pixels[i + 3] & 3;
    key[k++] = (uint8_t)(a + b * 4u + c * 16u + d * 64u);
  }
}

typedef struct {
  uint8_t key[16];
  int32_t index; /* 1-based pool index; 0 = empty */
} ExactSlot;

#define EXACT_CAP 512

static uint32_t hash_key16(const uint8_t key[16]) {
  uint32_t h = 2166136261u;
  int i;
  for (i = 0; i < 16; i++) {
    h ^= key[i];
    h *= 16777619u;
  }
  return h;
}

static int exact_lookup(ExactSlot *table, const uint8_t key[16]) {
  uint32_t h = hash_key16(key);
  int i;
  for (i = 0; i < EXACT_CAP; i++) {
    ExactSlot *slot = &table[(h + (uint32_t)i) % EXACT_CAP];
    if (slot->index == 0) return 0;
    if (memcmp(slot->key, key, 16) == 0) return slot->index;
  }
  return 0;
}

static void exact_insert(ExactSlot *table, const uint8_t key[16], int32_t index) {
  uint32_t h = hash_key16(key);
  int i;
  for (i = 0; i < EXACT_CAP; i++) {
    ExactSlot *slot = &table[(h + (uint32_t)i) % EXACT_CAP];
    if (slot->index == 0 || memcmp(slot->key, key, 16) == 0) {
      memcpy(slot->key, key, 16);
      slot->index = index;
      return;
    }
  }
}

int ppux_pack_flat_tol0(
  const uint8_t *flat,
  int w,
  int h,
  PpuxPoolEntry *out_pool,
  int32_t *out_unique_count,
  uint16_t *out_nametable
) {
  ExactSlot exact_table[EXACT_CAP];
  int32_t solid_pool_index[4] = {0, 0, 0, 0}; /* 1-based */
  int32_t unique = 0;
  int row, col, nt = 0;

  set_error("");
  if (!flat || !out_pool || !out_unique_count || !out_nametable) {
    set_error("null args");
    return PPUX_SKETCH_ERR_NULL;
  }
  if (w != PPUX_EXPECT_W || h != PPUX_EXPECT_H) {
    set_error("expected 256x240");
    return PPUX_SKETCH_ERR_DIMS;
  }

  memset(exact_table, 0, sizeof(exact_table));

  for (row = 0; row < PPUX_GRID_ROWS; row++) {
    for (col = 0; col < PPUX_GRID_COLS; col++) {
      uint8_t pixels[64];
      uint8_t key[16];
      int ox = col * PPUX_CELL;
      int oy = row * PPUX_CELL;
      int solid_shade;
      int32_t match_index = 0;
      int is_exact_solid;

      extract_tile(flat, w, ox, oy, pixels);
      solid_shade = canonical_solid_shade(pixels);
      if (solid_shade == 0 && solid_diff_count(pixels, 0, 0) > 0) {
        solid_shade = -1;
      }

      if (solid_shade >= 0) {
        match_index = solid_pool_index[solid_shade];
        is_exact_solid = (solid_diff_count(pixels, solid_shade, 0) == 0) ? 1 : 0;
        if (match_index == 0) {
          uint8_t solid_pixels[64];
          int i;
          if (unique >= PPUX_MAX_UNIQUE) {
            set_error("too many unique patterns");
            return PPUX_SKETCH_ERR_TOO_MANY_UNIQUE;
          }
          for (i = 0; i < 64; i++) solid_pixels[i] = (uint8_t)solid_shade;
          unique++;
          out_pool[unique - 1].x = ox;
          out_pool[unique - 1].y = oy;
          out_pool[unique - 1].solid_shade = solid_shade;
          out_pool[unique - 1].exact_solid = is_exact_solid;
          match_index = unique;
          solid_pool_index[solid_shade] = match_index;
          pattern_exact_key(solid_pixels, key);
          exact_insert(exact_table, key, match_index);
        } else {
          PpuxPoolEntry *entry = &out_pool[match_index - 1];
          if (entry->solid_shade == solid_shade && !entry->exact_solid && is_exact_solid) {
            entry->x = ox;
            entry->y = oy;
            entry->exact_solid = 1;
          }
        }
      } else {
        pattern_exact_key(pixels, key);
        match_index = exact_lookup(exact_table, key);
        if (match_index == 0) {
          if (unique >= PPUX_MAX_UNIQUE) {
            set_error("too many unique patterns");
            return PPUX_SKETCH_ERR_TOO_MANY_UNIQUE;
          }
          unique++;
          out_pool[unique - 1].x = ox;
          out_pool[unique - 1].y = oy;
          out_pool[unique - 1].solid_shade = -1;
          out_pool[unique - 1].exact_solid = 0;
          match_index = unique;
          exact_insert(exact_table, key, match_index);
        }
      }

      out_nametable[nt++] = (uint16_t)(match_index - 1);
    }
  }

  *out_unique_count = unique;
  return PPUX_SKETCH_OK;
}
