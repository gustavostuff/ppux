#ifndef PPUX_CLIPBOARD_INTERNAL_H
#define PPUX_CLIPBOARD_INTERNAL_H

#include "ppux_clipboard.h"

void ppux_clipboard_set_error(const char *msg);

int ppux_clipboard_platform_get_image(
  uint8_t **out_bytes,
  size_t *out_size,
  int32_t *out_format,
  int32_t *out_width,
  int32_t *out_height
);

#endif
