; NMI + wait_nmi
.export nmi, irq, wait_nmi
.importzp nmi_ready, soft2000, soft2001, scroll_x, scroll_y
.import apply_pending_palette

.segment "CODE"
nmi:
  pha
  txa
  pha
  tya
  pha

  ; Palette uploads first (still early vblank), then scroll / $2000 / $2001.
  jsr apply_pending_palette

  ; Scroll / $2000 before $2001 so enabling rendering never races a stale scroll.
  lda soft2000
  sta $2000
  lda scroll_x
  sta $2005
  lda scroll_y
  sta $2005
  lda soft2001
  sta $2001

  lda #1
  sta nmi_ready

  pla
  tay
  pla
  tax
  pla
  rti

irq:
  rti

wait_nmi:
  lda #0
  sta nmi_ready
@wait:
  lda nmi_ready
  beq @wait
  rts
