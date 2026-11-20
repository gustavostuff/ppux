#include "clipboard_internal.h"

#import <AppKit/AppKit.h>

#include <stdlib.h>
#include <string.h>

static int copy_data(NSData *data, uint8_t **out, size_t *out_size) {
  if (!data || data.length == 0) {
    return 0;
  }
  uint8_t *buf = (uint8_t *)malloc((size_t)data.length);
  if (!buf) {
    ppux_clipboard_set_error("out of memory");
    return 0;
  }
  memcpy(buf, data.bytes, (size_t)data.length);
  *out = buf;
  *out_size = (size_t)data.length;
  return 1;
}

int ppux_clipboard_platform_get_image(
  uint8_t **out_bytes,
  size_t *out_size,
  int32_t *out_format,
  int32_t *out_width,
  int32_t *out_height
) {
  @autoreleasepool {
    NSPasteboard *board = [NSPasteboard generalPasteboard];
    NSData *png = [board dataForType:NSPasteboardTypePNG];
    if (copy_data(png, out_bytes, out_size)) {
      *out_format = PPUX_CLIP_FMT_PNG;
      *out_width = 0;
      *out_height = 0;
      return PPUX_CLIP_OK;
    }

    NSImage *image = [[NSImage alloc] initWithPasteboard:board];
    if (!image) {
      ppux_clipboard_set_error("No image on the clipboard");
      return PPUX_CLIP_EMPTY;
    }
    NSData *tiff = [image TIFFRepresentation];
    NSBitmapImageRep *rep = tiff ? [NSBitmapImageRep imageRepWithData:tiff] : nil;
    NSData *encoded = rep ? [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] : nil;
    if (!copy_data(encoded, out_bytes, out_size)) {
      ppux_clipboard_set_error("Could not encode clipboard image");
      return PPUX_CLIP_ERR;
    }
    *out_format = PPUX_CLIP_FMT_PNG;
    *out_width = 0;
    *out_height = 0;
    return PPUX_CLIP_OK;
  }
}

int ppux_clipboard_platform_set_png(const uint8_t *bytes, size_t size) {
  @autoreleasepool {
    if (!bytes || size == 0) {
      ppux_clipboard_set_error("empty png");
      return PPUX_CLIP_ERR;
    }
    NSPasteboard *board = [NSPasteboard generalPasteboard];
    [board clearContents];
    NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)size];
    if (![board setData:data forType:NSPasteboardTypePNG]) {
      ppux_clipboard_set_error("Could not set clipboard image");
      return PPUX_CLIP_ERR;
    }
    return PPUX_CLIP_OK;
  }
}
