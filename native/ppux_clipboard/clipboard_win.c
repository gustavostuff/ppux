#include "clipboard_internal.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdlib.h>
#include <string.h>

static int copy_global(HANDLE handle, uint8_t **out, size_t *out_size) {
  if (!handle) {
    return 0;
  }
  SIZE_T n = GlobalSize(handle);
  void *locked = GlobalLock(handle);
  if (!locked || n == 0) {
    if (locked) {
      GlobalUnlock(handle);
    }
    return 0;
  }
  uint8_t *buf = (uint8_t *)malloc((size_t)n);
  if (!buf) {
    GlobalUnlock(handle);
    ppux_clipboard_set_error("out of memory");
    return 0;
  }
  memcpy(buf, locked, (size_t)n);
  GlobalUnlock(handle);
  *out = buf;
  *out_size = (size_t)n;
  return 1;
}

static int take_encoded(UINT format, int32_t clip_format, uint8_t **out_bytes, size_t *out_size, int32_t *out_format) {
  if (!format || !IsClipboardFormatAvailable(format)) {
    return 0;
  }
  HANDLE handle = GetClipboardData(format);
  if (!copy_global(handle, out_bytes, out_size)) {
    return 0;
  }
  *out_format = clip_format;
  return 1;
}

int ppux_clipboard_platform_get_image(
  uint8_t **out_bytes,
  size_t *out_size,
  int32_t *out_format,
  int32_t *out_width,
  int32_t *out_height
) {
  UINT png_fmt = RegisterClipboardFormatA("PNG");
  UINT png_mime = RegisterClipboardFormatA("image/png");

  int opened = 0;
  for (int attempt = 0; attempt < 5; attempt++) {
    if (OpenClipboard(NULL)) {
      opened = 1;
      break;
    }
    Sleep(10);
  }
  if (!opened) {
    ppux_clipboard_set_error("OpenClipboard failed");
    return PPUX_CLIP_ERR;
  }

  int rc = PPUX_CLIP_EMPTY;
  if (take_encoded(png_fmt, PPUX_CLIP_FMT_PNG, out_bytes, out_size, out_format)
    || take_encoded(png_mime, PPUX_CLIP_FMT_PNG, out_bytes, out_size, out_format)) {
    *out_width = 0;
    *out_height = 0;
    rc = PPUX_CLIP_OK;
  } else if (IsClipboardFormatAvailable(CF_DIBV5) || IsClipboardFormatAvailable(CF_DIB)) {
    UINT dib_fmt = IsClipboardFormatAvailable(CF_DIBV5) ? CF_DIBV5 : CF_DIB;
    HANDLE handle = GetClipboardData(dib_fmt);
    uint8_t *dib = NULL;
    size_t dib_size = 0;
    if (!copy_global(handle, &dib, &dib_size)) {
      ppux_clipboard_set_error("Could not read clipboard DIB");
      rc = PPUX_CLIP_ERR;
    } else {
      uint8_t *rgba = NULL;
      int32_t w = 0;
      int32_t h = 0;
      int decoded = ppux_dib_to_rgba(dib, dib_size, &rgba, &w, &h);
      free(dib);
      if (decoded != 0 || !rgba) {
        ppux_clipboard_set_error("Could not decode clipboard DIB");
        rc = PPUX_CLIP_ERR;
      } else {
        *out_bytes = rgba;
        *out_size = (size_t)w * (size_t)h * 4u;
        *out_format = PPUX_CLIP_FMT_RGBA8;
        *out_width = w;
        *out_height = h;
        rc = PPUX_CLIP_OK;
      }
    }
  } else {
    ppux_clipboard_set_error("No image on the clipboard");
    rc = PPUX_CLIP_EMPTY;
  }

  CloseClipboard();
  return rc;
}
