; Nametable payloads (1024B = 960 tiles + 64 attrs) + pointer table.
.export nametable_ptrs

.segment "RODATA"
nametable_slide00: .incbin "data/nam/slide00.nam"
nametable_slide01: .incbin "data/nam/slide01.nam"
nametable_slide02: .incbin "data/nam/slide02.nam"
nametable_slide03: .incbin "data/nam/slide03.nam"
nametable_slide04: .incbin "data/nam/slide04.nam"
nametable_slide05: .incbin "data/nam/slide05.nam"
nametable_slide06: .incbin "data/nam/slide06.nam"
nametable_slide07: .incbin "data/nam/slide07.nam"
nametable_slide08: .incbin "data/nam/slide08.nam"
nametable_slide09: .incbin "data/nam/slide09.nam"
nametable_slide10: .incbin "data/nam/slide10.nam"
nametable_slide11: .incbin "data/nam/slide11.nam"
nametable_slide12: .incbin "data/nam/slide12.nam"
nametable_slide13: .incbin "data/nam/slide13.nam"
nametable_slide14: .incbin "data/nam/slide14.nam"
nametable_slide15: .incbin "data/nam/slide15.nam"

nametable_ptrs:
  .addr nametable_slide00, nametable_slide01, nametable_slide02, nametable_slide03
  .addr nametable_slide04, nametable_slide05, nametable_slide06, nametable_slide07
  .addr nametable_slide08, nametable_slide09, nametable_slide10, nametable_slide11
  .addr nametable_slide12, nametable_slide13, nametable_slide14, nametable_slide15
