; Nametable pointers + slide rebuild helpers.
.export copy_nametable_1024
.export rebuild_slide
.import nametable_ptrs
.import slide_count
.importzp slide_index, need_rebuild, soft2000, soft2001, scroll_x, scroll_y
.importzp ptr_lo, ptr_hi, tmp0, tmp1
.import cnrom_set_chr_bank
.import copy_palette_32
.import wait_nmi

.segment "CODE"
copy_nametable_1024:
  lda slide_index
  asl a
  tax
  lda nametable_ptrs, x
  sta ptr_lo
  lda nametable_ptrs+1, x
  sta ptr_hi

  lda #$20
  sta $2006
  lda #$00
  sta $2006

  ldy #0
  ldx #4          ; 4 x 256 = 1024
@page:
  lda (ptr_lo), y
  sta $2007
  iny
  bne @page
  inc ptr_hi
  dex
  bne @page
  rts

; Full slide swap: PPU off -> palette (vblank) -> CHR bank -> NT -> scroll -> PPU on.
;
; Palette must be written while still in vblank. With rendering off, if PPUADDR
; sits in $3Fxx the backdrop tracks that entry - a mid-frame palette upload
; shows up as a colored horizontal band (~scanline 120 after a 1KB NT copy).
rebuild_slide:
  lda #0
  sta soft2001
  jsr wait_nmi

  ; Still early vblank: palette first, then leave $3Fxx immediately.
  jsr copy_palette_32
  lda #$20
  sta $2006
  lda #$00
  sta $2006

  lda slide_index
  jsr cnrom_set_chr_bank
  jsr copy_nametable_1024

  ; Scroll soft regs; NMI applies $2005 before enabling rendering.
  lda #0
  sta scroll_x
  sta scroll_y

  lda #%10000000   ; NMI on, BG pattern $0000, nametable 0
  sta soft2000
  lda #%00001010   ; show background
  sta soft2001
  jsr wait_nmi

  lda #0
  sta need_rebuild
  rts
