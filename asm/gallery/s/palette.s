; Per-slide palette sets via .incbin from data/pal/slideNN/.
;   main.pal     - 32 bytes (full-bright rest palette)
;   fade_out.pal - 128 bytes = 4 x 32 darken steps ending in all $0F
; Sprite color-0 slots ($3F10/$14/$18/$1C) mirror BG color 0 ($3F00);
; exporters copy BG0 into those slots so a full 32-byte upload keeps the backdrop.
.export palette_ptrs
.export fade_out_ptrs
.export copy_palette_32
.export copy_fade_step
.export copy_palette_black
.export apply_pending_palette
.importzp slide_index, ptr_lo, ptr_hi, tmp0
.importzp fade_step, fade_apply

FADE_APPLY_NONE = 0
FADE_APPLY_STEP = 1
FADE_APPLY_MAIN = 2
FADE_STEPS = 4

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

fade_out_slide00: .incbin "../data/pal/slide00/fade_out.pal"
fade_out_slide01: .incbin "../data/pal/slide01/fade_out.pal"
fade_out_slide02: .incbin "../data/pal/slide02/fade_out.pal"
fade_out_slide03: .incbin "../data/pal/slide03/fade_out.pal"
fade_out_slide04: .incbin "../data/pal/slide04/fade_out.pal"
fade_out_slide05: .incbin "../data/pal/slide05/fade_out.pal"
fade_out_slide06: .incbin "../data/pal/slide06/fade_out.pal"
fade_out_slide07: .incbin "../data/pal/slide07/fade_out.pal"
fade_out_slide08: .incbin "../data/pal/slide08/fade_out.pal"
fade_out_slide09: .incbin "../data/pal/slide09/fade_out.pal"
fade_out_slide10: .incbin "../data/pal/slide10/fade_out.pal"
fade_out_slide11: .incbin "../data/pal/slide11/fade_out.pal"
fade_out_slide12: .incbin "../data/pal/slide12/fade_out.pal"
fade_out_slide13: .incbin "../data/pal/slide13/fade_out.pal"
fade_out_slide14: .incbin "../data/pal/slide14/fade_out.pal"
fade_out_slide15: .incbin "../data/pal/slide15/fade_out.pal"

palette_ptrs:
  .addr palette_slide00, palette_slide01, palette_slide02, palette_slide03
  .addr palette_slide04, palette_slide05, palette_slide06, palette_slide07
  .addr palette_slide08, palette_slide09, palette_slide10, palette_slide11
  .addr palette_slide12, palette_slide13, palette_slide14, palette_slide15

fade_out_ptrs:
  .addr fade_out_slide00, fade_out_slide01, fade_out_slide02, fade_out_slide03
  .addr fade_out_slide04, fade_out_slide05, fade_out_slide06, fade_out_slide07
  .addr fade_out_slide08, fade_out_slide09, fade_out_slide10, fade_out_slide11
  .addr fade_out_slide12, fade_out_slide13, fade_out_slide14, fade_out_slide15

.segment "CODE"

; Upload 32 bytes from (ptr_lo/ptr_hi) to $3F00.
upload_palette_ptr:
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

; Point ptr at palette_ptrs[slide_index].
load_main_palette_ptr:
  lda slide_index
  asl a
  tax
  lda palette_ptrs, x
  sta ptr_lo
  lda palette_ptrs+1, x
  sta ptr_hi
  rts

; Point ptr at fade_out_ptrs[slide_index] + fade_step * 32.
load_fade_step_ptr:
  lda slide_index
  asl a
  tax
  lda fade_out_ptrs, x
  sta ptr_lo
  lda fade_out_ptrs+1, x
  sta ptr_hi
  lda fade_step
  beq @done
  sta tmp0
@add32:
  clc
  lda ptr_lo
  adc #32
  sta ptr_lo
  bcc @noinc
  inc ptr_hi
@noinc:
  dec tmp0
  bne @add32
@done:
  rts

copy_palette_32:
  jsr load_main_palette_ptr
  jmp upload_palette_ptr

copy_fade_step:
  jsr load_fade_step_ptr
  jmp upload_palette_ptr

; Force all $0F (universal black for gallery fades).
copy_palette_black:
  lda #$3F
  sta $2006
  lda #$00
  sta $2006
  ldy #32
  lda #$0F
@loop:
  sta $2007
  dey
  bne @loop
  rts

; Called from NMI while still in vblank (before $2001).
apply_pending_palette:
  lda fade_apply
  beq @done
  cmp #FADE_APPLY_MAIN
  beq @main
  cmp #FADE_APPLY_STEP
  beq @step
  lda #FADE_APPLY_NONE
  sta fade_apply
  rts
@main:
  lda #FADE_APPLY_NONE
  sta fade_apply
  jmp copy_palette_32
@step:
  lda #FADE_APPLY_NONE
  sta fade_apply
  jmp copy_fade_step
@done:
  rts
