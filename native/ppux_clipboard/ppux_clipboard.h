#ifndef PPUX_CLIPBOARD_H
#define PPUX_CLIPBOARD_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
  PPUX_CLIP_OK = 0,
  PPUX_CLIP_EMPTY = 1,
  PPUX_CLIP_UNAVAILABLE = 2,
  PPUX_CLIP_ERR = 3
};

enum {
  PPUX_CLIP_FMT_PNG = 1,
  PPUX_CLIP_FMT_BMP = 2,
  PPUX_CLIP_FMT_RGBA8 = 3
};

/* out_bytes is malloc'd. Caller frees it with ppux_clipboard_free.
 * PNG and BMP set width/height to 0. RGBA8 sets them and stores
 * top-down straight alpha, 4 bytes per pixel.
 * Returns PPUX_CLIP_OK, EMPTY (no image), UNAVAILABLE (no helper
 * backend), or ERR. ppux_clipboard_last_error() is set on failure.
 */
int ppux_clipboard_get_image(
  uint8_t **out_bytes,
  size_t *out_size,
  int32_t *out_format,
  int32_t *out_width,
  int32_t *out_height
);

void ppux_clipboard_free(void *p);

const char *ppux_clipboard_last_error(void);

/* Copy PNG bytes onto the OS clipboard. Linux keeps serving the image
 * until another copy replaces it or this process exits. Returns
 * PPUX_CLIP_OK, UNAVAILABLE, or ERR.
 */
int ppux_clipboard_set_png(const uint8_t *bytes, size_t size);

/* Decode a clipboard CF_DIB / CF_DIBV5 blob to top-down RGBA8.
 * Returns 0 on success. *out_rgba is malloc'd.
 */
int ppux_dib_to_rgba(
  const uint8_t *dib,
  size_t dib_size,
  uint8_t **out_rgba,
  int32_t *out_w,
  int32_t *out_h
);

#ifdef __cplusplus
}
#endif

#endif
