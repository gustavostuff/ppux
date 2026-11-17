#include "ppux_clipboard.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void expect_eq_u8(const char *name, uint8_t got, uint8_t want) {
  if (got != want) {
    fprintf(stderr, "%s: got %u want %u\n", name, (unsigned)got, (unsigned)want);
    exit(1);
  }
}

static void write_u16(uint8_t *p, uint16_t v) {
  p[0] = (uint8_t)(v & 0xFF);
  p[1] = (uint8_t)((v >> 8) & 0xFF);
}

static void write_u32(uint8_t *p, uint32_t v) {
  p[0] = (uint8_t)(v & 0xFF);
  p[1] = (uint8_t)((v >> 8) & 0xFF);
  p[2] = (uint8_t)((v >> 16) & 0xFF);
  p[3] = (uint8_t)((v >> 24) & 0xFF);
}

static void write_i32(uint8_t *p, int32_t v) {
  write_u32(p, (uint32_t)v);
}

/* 2x2 bottom-up 24-bit BI_RGB.
 * Top-left red, top-right green, bottom-left blue, bottom-right white.
 * Stored bottom row first, BGR, stride 8.
 */
static void test_bottom_up_24(void) {
  uint8_t dib[40 + 16];
  memset(dib, 0, sizeof(dib));
  write_u32(dib + 0, 40);
  write_i32(dib + 4, 2);
  write_i32(dib + 8, 2);
  write_u16(dib + 12, 1);
  write_u16(dib + 14, 24);
  write_u32(dib + 16, 0);
  /* bottom row: blue, white */
  dib[40 + 0] = 255; dib[40 + 1] = 0; dib[40 + 2] = 0;
  dib[40 + 3] = 255; dib[40 + 4] = 255; dib[40 + 5] = 255;
  /* top row: red, green */
  dib[48 + 0] = 0; dib[48 + 1] = 0; dib[48 + 2] = 255;
  dib[48 + 3] = 0; dib[48 + 4] = 255; dib[48 + 5] = 0;

  uint8_t *rgba = NULL;
  int32_t w = 0;
  int32_t h = 0;
  int rc = ppux_dib_to_rgba(dib, sizeof(dib), &rgba, &w, &h);
  if (rc != 0 || !rgba || w != 2 || h != 2) {
    fprintf(stderr, "24-bit DIB decode failed rc=%d\n", rc);
    exit(1);
  }
  expect_eq_u8("tl r", rgba[0], 255);
  expect_eq_u8("tl g", rgba[1], 0);
  expect_eq_u8("tl b", rgba[2], 0);
  expect_eq_u8("tl a", rgba[3], 255);
  expect_eq_u8("tr r", rgba[4], 0);
  expect_eq_u8("tr g", rgba[5], 255);
  expect_eq_u8("tr b", rgba[6], 0);
  expect_eq_u8("bl r", rgba[8], 0);
  expect_eq_u8("bl g", rgba[9], 0);
  expect_eq_u8("bl b", rgba[10], 255);
  expect_eq_u8("br r", rgba[12], 255);
  expect_eq_u8("br g", rgba[13], 255);
  expect_eq_u8("br b", rgba[14], 255);
  free(rgba);
}

/* 1x2 bottom-up 32-bit BI_BITFIELDS. Masks are BGRA byte order in memory
 * as R=0x00FF0000, G=0x0000FF00, B=0x000000FF. High byte is ignored.
 * Bottom pixel RGB 1,2,3. Top pixel RGB 4,5,6.
 */
static void test_bottom_up_32_bitfields(void) {
  uint8_t dib[52 + 8];
  memset(dib, 0, sizeof(dib));
  write_u32(dib + 0, 40);
  write_i32(dib + 4, 1);
  write_i32(dib + 8, 2);
  write_u16(dib + 12, 1);
  write_u16(dib + 14, 32);
  write_u32(dib + 16, 3);
  write_u32(dib + 40, 0x00FF0000u);
  write_u32(dib + 44, 0x0000FF00u);
  write_u32(dib + 48, 0x000000FFu);
  /* bottom pixel B,G,R,x = 3,2,1,0 */
  dib[52 + 0] = 3;
  dib[52 + 1] = 2;
  dib[52 + 2] = 1;
  dib[52 + 3] = 0;
  /* top pixel B,G,R,x = 6,5,4,0 */
  dib[56 + 0] = 6;
  dib[56 + 1] = 5;
  dib[56 + 2] = 4;
  dib[56 + 3] = 0;

  uint8_t *rgba = NULL;
  int32_t w = 0;
  int32_t h = 0;
  int rc = ppux_dib_to_rgba(dib, sizeof(dib), &rgba, &w, &h);
  if (rc != 0 || !rgba || w != 1 || h != 2) {
    fprintf(stderr, "32-bit DIB decode failed rc=%d\n", rc);
    exit(1);
  }
  expect_eq_u8("top r", rgba[0], 4);
  expect_eq_u8("top g", rgba[1], 5);
  expect_eq_u8("top b", rgba[2], 6);
  expect_eq_u8("top a", rgba[3], 255);
  expect_eq_u8("bot r", rgba[4], 1);
  expect_eq_u8("bot g", rgba[5], 2);
  expect_eq_u8("bot b", rgba[6], 3);
  expect_eq_u8("bot a", rgba[7], 255);
  free(rgba);
}

static void test_rejects_short_buffer(void) {
  uint8_t dib[20];
  memset(dib, 0, sizeof(dib));
  uint8_t *rgba = NULL;
  int32_t w = 0;
  int32_t h = 0;
  int rc = ppux_dib_to_rgba(dib, sizeof(dib), &rgba, &w, &h);
  if (rc == 0 || rgba) {
    fprintf(stderr, "short DIB should fail\n");
    exit(1);
  }
}

int main(void) {
  test_bottom_up_24();
  test_bottom_up_32_bitfields();
  test_rejects_short_buffer();
  printf("dib_to_rgba ok\n");
  return 0;
}
