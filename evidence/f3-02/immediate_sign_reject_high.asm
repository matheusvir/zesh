; F3-02 Q-B3: above-range immediate (must reject).
; Hypothesis: assembler reports an error; no process is created.
MV W0, #65536
SYSCALL #2
