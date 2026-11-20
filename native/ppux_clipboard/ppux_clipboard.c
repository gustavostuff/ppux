#include "clipboard_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char g_err[512];

void ppux_clipboard_set_error(const char *msg) {
  if (!msg) {
    msg = "";
  }
  snprintf(g_err, sizeof(g_err), "%s", msg);
}

const char *ppux_clipboard_last_error(void) {
  return g_err;
}

void ppux_clipboard_free(void *p) {
  free(p);
}

int ppux_clipboard_get_image(
  uint8_t **out_bytes,
  size_t *out_size,
  int32_t *out_format,
  int32_t *out_width,
  int32_t *out_height
) {
  g_err[0] = '\0';
  if (!out_bytes || !out_size || !out_format || !out_width || !out_height) {
    ppux_clipboard_set_error("null argument");
    return PPUX_CLIP_ERR;
  }
  *out_bytes = NULL;
  *out_size = 0;
  *out_format = 0;
  *out_width = 0;
  *out_height = 0;
  return ppux_clipboard_platform_get_image(
    out_bytes, out_size, out_format, out_width, out_height
  );
}

int ppux_clipboard_set_png(const uint8_t *bytes, size_t size) {
  g_err[0] = '\0';
  if (!bytes || size == 0) {
    ppux_clipboard_set_error("empty png");
    return PPUX_CLIP_ERR;
  }
  return ppux_clipboard_platform_set_png(bytes, size);
}
