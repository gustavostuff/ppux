; Controller 1 read — standard shift into pad_state:
; bit0=A … bit6=Left, bit7=Right
.importzp pad_state, pad_prev, tmp0

.export read_pad1
.export pad_edge

.segment "CODE"
read_pad1:
  lda pad_state
  sta pad_prev

  lda #$01
  sta $4016
  lda #$00
  sta $4016

  lda #0
  sta pad_state
  ldx #8
@read:
  lda $4016
  lsr a              ; button -> C
  ror pad_state      ; C -> bit7, eventually bit0=A … bit7=Right
  dex
  bne @read
  rts

; A = button mask; returns A = newly pressed bits for that mask (0 if none).
pad_edge:
  sta tmp0
  lda pad_prev
  eor #$FF
  and pad_state
  and tmp0
  rts
