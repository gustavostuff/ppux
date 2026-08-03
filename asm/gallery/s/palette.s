; Per-slide palette sets (32 bytes each). Hardcoded v1 — all slides identical.
; BG0-3: 07 17 27 36 × 4
; SPR0-3: 07 0F 0F 0F × 4
; Sprite color-0 slots ($3F10/$14/$18/$1C) mirror BG color 0 ($3F00/…);
; writing $0F there after BG would stomp the backdrop to black.
.export palette_ptrs
.export copy_palette_32
.importzp slide_index, ptr_lo, ptr_hi

.segment "RODATA"
.macro gallery_pal
  .byte $07,$17,$27,$36
  .byte $07,$17,$27,$36
  .byte $07,$17,$27,$36
  .byte $07,$17,$27,$36
  .byte $07,$0F,$0F,$0F
  .byte $07,$0F,$0F,$0F
  .byte $07,$0F,$0F,$0F
  .byte $07,$0F,$0F,$0F
.endmacro

palette_slide00: gallery_pal
palette_slide01: gallery_pal
palette_slide02: gallery_pal
palette_slide03: gallery_pal
palette_slide04: gallery_pal
palette_slide05: gallery_pal
palette_slide06: gallery_pal
palette_slide07: gallery_pal
palette_slide08: gallery_pal
palette_slide09: gallery_pal
palette_slide10: gallery_pal
palette_slide11: gallery_pal
palette_slide12: gallery_pal
palette_slide13: gallery_pal
palette_slide14: gallery_pal
palette_slide15: gallery_pal

palette_ptrs:
  .addr palette_slide00, palette_slide01, palette_slide02, palette_slide03
  .addr palette_slide04, palette_slide05, palette_slide06, palette_slide07
  .addr palette_slide08, palette_slide09, palette_slide10, palette_slide11
  .addr palette_slide12, palette_slide13, palette_slide14, palette_slide15

.segment "CODE"
copy_palette_32:
  lda slide_index
  asl a
  tax
  lda palette_ptrs, x
  sta ptr_lo
  lda palette_ptrs+1, x
  sta ptr_hi

  lda #$3F
  sta $2006
  lda #$00
  sta $2006

  ldy #0
@loop:
  lda (ptr_lo), y
  sta $2007
  iny
  cpy #32
  bne @loop
  rts
