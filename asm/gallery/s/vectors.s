; Interrupt vectors
.import nmi, reset, irq

.segment "VECTORS"
  .addr nmi
  .addr reset
  .addr irq
