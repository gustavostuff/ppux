; CNROM banktable (bus-conflict safe writes).
.importzp tmp0

.export cnrom_set_chr_bank
.export banktable

.segment "RODATA"
banktable:
  .byte $00,$01,$02,$03,$04,$05,$06,$07
  .byte $08,$09,$0A,$0B,$0C,$0D,$0E,$0F

.segment "CODE"
; A = bank 0..15
cnrom_set_chr_bank:
  sta tmp0
  tay
  lda banktable, y
  sta banktable, y
  rts
