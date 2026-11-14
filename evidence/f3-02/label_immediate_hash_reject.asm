; F3-02 Q-A3: hash-prefixed label as MV immediate (must reject).
; Hypothesis: assembler reports an error; no process is created.
MV W0, #alvo
alvo:
MV W1, #7
SYSCALL #2
