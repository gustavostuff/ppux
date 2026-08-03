; Per-slide palette sets (32 bytes each) via .incbin from data/pal/slideNN/main.pal.
; Folder layout reserves room for future fade_in.pal / fade_out.pal.
; Sprite color-0 slots ($3F10/$14/$18/$1C) mirror BG color 0 ($3F00);
; exporters copy BG0 into those slots so a full 32-byte upload keeps the backdrop.
.export palette_ptrs
.export copy_palette_32
.importzp slide_index, ptr_lo, ptr_hi

.segment "RODATA"
palette_slide00: .incbin "../data/pal/slide00/main.pal"
palette_slide01: .incbin "../data/pal/slide01/main.pal"
palette_slide02: .incbin "../data/pal/slide02/main.pal"
palette_slide03: .incbin "../data/pal/slide03/main.pal"
palette_slide04: .incbin "../data/pal/slide04/main.pal"
palette_slide05: .incbin "../data/pal/slide05/main.pal"
palette_slide06: .incbin "../data/pal/slide06/main.pal"
palette_slide07: .incbin "../data/pal/slide07/main.pal"
palette_slide08: .incbin "../data/pal/slide08/main.pal"
palette_slide09: .incbin "../data/pal/slide09/main.pal"
palette_slide10: .incbin "../data/pal/slide10/main.pal"
palette_slide11: .incbin "../data/pal/slide11/main.pal"
palette_slide12: .incbin "../data/pal/slide12/main.pal"
palette_slide13: .incbin "../data/pal/slide13/main.pal"
palette_slide14: .incbin "../data/pal/slide14/main.pal"
palette_slide15: .incbin "../data/pal/slide15/main.pal"

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
