; Shared ZP / BSS symbols for the gallery ROM.

.exportzp nmi_ready, soft2000, soft2001, scroll_x, scroll_y
.exportzp pad_state, pad_prev, slide_index, need_rebuild
.exportzp ptr_lo, ptr_hi, tmp0, tmp1

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

.segment "BSS"
