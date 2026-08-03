; Main loop: edge-detect Left/Right, rebuild slide.
.export main
.import read_pad1, pad_edge
.importzp slide_index, need_rebuild
.import slide_count
.import rebuild_slide
.import wait_nmi

BUTTON_LEFT  = %01000000
BUTTON_RIGHT = %10000000

.segment "CODE"
main:
@frame:
  jsr wait_nmi
  jsr read_pad1

  lda #BUTTON_LEFT
  jsr pad_edge
  beq @check_right
  lda slide_index
  beq @wrap_left
  dec slide_index
  jmp @mark
@wrap_left:
  lda slide_count
  sec
  sbc #1
  sta slide_index
@mark:
  lda #1
  sta need_rebuild

@check_right:
  lda #BUTTON_RIGHT
  jsr pad_edge
  beq @maybe_rebuild
  inc slide_index
  lda slide_index
  cmp slide_count
  bcc @mark_right
  lda #0
  sta slide_index
@mark_right:
  lda #1
  sta need_rebuild

@maybe_rebuild:
  lda need_rebuild
  beq @frame
  jsr rebuild_slide
  jmp @frame
