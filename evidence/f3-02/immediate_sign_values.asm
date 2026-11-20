; F3-02 Q-B1: boundary and in-range immediates through MV.
; Layout: 5x MV + SYSCALL #2 = 6 instructions.
; Hypothesis: all five assemble; execution sign-extends the uint16 immediate,
; so W0=-1, W1=-32768, W2=32767, W3=-32768 (from 32768), W4=-1 (from 65535).
MV W0, #-1
MV W1, #-32768
MV W2, #32767
MV W3, #32768
MV W4, #65535
SYSCALL #2
