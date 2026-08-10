; Main loop: Left/Right navigate slides (optional fade, optional title-once).
.export main
.import read_pad1, pad_edge
.importzp slide_index
.importzp fade_mode, fade_step, fade_timer, fade_target, fade_apply
.import slide_count, fade_hold, use_transitions, show_first_once
.import rebuild_slide
.import rebuild_slide_keep_black
.import wait_nmi

BUTTON_LEFT  = %01000000
BUTTON_RIGHT = %10000000

FADE_MODE_IDLE = 0
FADE_MODE_OUT  = 1
FADE_MODE_IN   = 2
FADE_APPLY_STEP = 1
FADE_APPLY_MAIN = 2
FADE_STEPS = 4

.segment "CODE"

; A = candidate slide index.
; Sets fade_target and either hard-cuts or starts fade-out.
begin_slide_change:
  cmp slide_index
  beq @noop
  sta fade_target
  lda use_transitions
  beq @hard_cut

  lda #FADE_MODE_OUT
  sta fade_mode
  lda #0
  sta fade_step
  lda fade_hold
  sta fade_timer
  lda #FADE_APPLY_STEP
  sta fade_apply
  rts

@hard_cut:
  lda fade_target
  sta slide_index
  jsr rebuild_slide
@noop:
  rts

; Compute previous slide into A (Left).
prev_slide_index:
  lda show_first_once
  beq @normal
  lda slide_count
  cmp #2
  bcc @normal
  ; Title-once: leaving slide 0 goes to last; wrap inside 1..count-1.
  lda slide_index
  beq @to_last
  cmp #1
  beq @to_last
  sec
  sbc #1
  rts
@to_last:
  lda slide_count
  sec
  sbc #1
  rts

@normal:
  lda slide_index
  beq @wrap_left
  sec
  sbc #1
  rts
@wrap_left:
  lda slide_count
  sec
  sbc #1
  rts

; Compute next slide into A (Right).
next_slide_index:
  lda show_first_once
  beq @normal
  lda slide_count
  cmp #2
  bcc @normal
  lda slide_index
  bne @not_title
  lda #1
  rts
@not_title:
  clc
  adc #1
  cmp slide_count
  bcc @done
  lda #1
@done:
  rts

@normal:
  lda slide_index
  clc
  adc #1
  cmp slide_count
  bcc @ok
  lda #0
@ok:
  rts

main:
@frame:
  jsr wait_nmi
  jsr read_pad1

  lda fade_mode
  bne @tick_fade

  lda #BUTTON_LEFT
  jsr pad_edge
  beq @check_right
  jsr prev_slide_index
  jsr begin_slide_change
  jmp @frame

@check_right:
  lda #BUTTON_RIGHT
  jsr pad_edge
  beq @frame
  jsr next_slide_index
  jsr begin_slide_change
  jmp @frame

@tick_fade:
  dec fade_timer
  bne @frame

  lda fade_mode
  cmp #FADE_MODE_OUT
  beq @fade_out_advance
  ; Fade-in path
  lda fade_step
  beq @fade_in_to_main
  dec fade_step
  lda fade_hold
  sta fade_timer
  lda #FADE_APPLY_STEP
  sta fade_apply
  jmp @frame

@fade_in_to_main:
  lda #FADE_APPLY_MAIN
  sta fade_apply
  lda #FADE_MODE_IDLE
  sta fade_mode
  jmp @frame

@fade_out_advance:
  lda fade_step
  cmp #FADE_STEPS - 1
  beq @swap_at_black
  inc fade_step
  lda fade_hold
  sta fade_timer
  lda #FADE_APPLY_STEP
  sta fade_apply
  jmp @frame

@swap_at_black:
  lda fade_target
  sta slide_index
  jsr rebuild_slide_keep_black
  lda #FADE_MODE_IN
  sta fade_mode
  lda #FADE_STEPS - 2
  sta fade_step
  lda fade_hold
  sta fade_timer
  lda #FADE_APPLY_STEP
  sta fade_apply
  jmp @frame
