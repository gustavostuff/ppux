; Shared ZP / BSS symbols for the gallery ROM.

.exportzp nmi_ready, soft2000, soft2001, scroll_x, scroll_y
.exportzp pad_state, pad_prev, slide_index, need_rebuild
.exportzp ptr_lo, ptr_hi, tmp0, tmp1
.exportzp fade_mode, fade_step, fade_timer, fade_target, fade_apply

; fade_mode: 0=idle, 1=fade out, 2=fade in
; fade_apply: 0=none, 1=upload fade_out[fade_step], 2=upload main.pal
FADE_MODE_IDLE = 0
FADE_MODE_OUT  = 1
FADE_MODE_IN   = 2
FADE_APPLY_NONE = 0
FADE_APPLY_STEP = 1
FADE_APPLY_MAIN = 2

.segment "ZEROPAGE"
nmi_ready:      .res 1
soft2000:       .res 1
soft2001:       .res 1
scroll_x:       .res 1
scroll_y:       .res 1
pad_state:      .res 1
pad_prev:       .res 1
slide_index:    .res 1
need_rebuild:   .res 1
ptr_lo:         .res 1
ptr_hi:         .res 1
tmp0:           .res 1
tmp1:           .res 1
fade_mode:      .res 1
fade_step:      .res 1
fade_timer:     .res 1
fade_target:    .res 1
fade_apply:     .res 1

.segment "BSS"
