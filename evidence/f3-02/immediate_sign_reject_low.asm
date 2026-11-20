; F3-02 Q-B2: below-range immediate (must reject).
; Hypothesis: assembler reports an error; no process is created.
MV W0, #-32769
SYSCALL #2
