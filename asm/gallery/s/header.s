; header.s - NES 2.0, mapper 3 (CNROM), 2x16KB PRG, 16x8KB CHR
;
; Byte 8 (NES 2.0): high mapper nibble in bits 0-3, submapper in bits 4-7.
; Submapper 1 (no bus conflicts) => $10.  ($01 wrongly set mapper to 259!)
.segment "HEADER"
  .byte "NES", $1A
  .byte 2          ; 32 KB PRG
  .byte 16         ; 16 x 8 KB CHR (oversize CNROM)
  .byte $30        ; mapper 3 low nybble; vertical arrangement (H mirroring)
  .byte $08        ; NES 2.0 id (bits 3-2 = 10); mapper mid nybble 0
  .byte $10        ; submapper 1, mapper high nibble 0  => mapper 3
  .byte $00
  .byte $00        ; no PRG-RAM
  .byte $00        ; no CHR-RAM
  .byte $00        ; NTSC
  .byte $00
  .byte $00
  .byte $00
