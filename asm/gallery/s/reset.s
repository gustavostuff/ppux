; RESET / PPU warm-up
.export reset
.importzp nmi_ready, soft2000, soft2001, scroll_x, scroll_y
.importzp pad_state, pad_prev, slide_index, need_rebuild
.importzp fade_mode, fade_step, fade_timer, fade_target, fade_apply
.import wait_nmi
.import rebuild_slide
.import main

.segment "CODE"
reset:
  sei
  cld
  ldx #$40
  stx $4017
  ldx #$FF
  txs
  inx
  stx $2000
  stx $2001
  stx $4010

  ; First vblank wait
@vwait1:
  bit $2002
  bpl @vwait1

  ; Clear RAM
  lda #0
@clear:
  sta $0000, x
  sta $0100, x
  sta $0200, x
  sta $0300, x
  sta $0400, x
  sta $0500, x
  sta $0600, x
  sta $0700, x
  inx
  bne @clear

@vwait2:
  bit $2002
  bpl @vwait2

  lda #0
  sta slide_index
  sta pad_state
  sta pad_prev
  sta scroll_x
  sta scroll_y
  sta fade_mode
  sta fade_step
  sta fade_timer
  sta fade_target
  sta fade_apply
  lda #%10000000
  sta soft2000
  sta $2000          ; enable NMI for wait_nmi
  lda #0
  sta soft2001

  lda #1
  sta need_rebuild
  jsr rebuild_slide
  jmp main
