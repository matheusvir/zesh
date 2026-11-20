; F3-02 Q-A1: forward label as MV immediate (no #).
; Layout: instr 0 MV W0, alvo | instr 1 MV W1, #0 | instr 2 alvo: MV W1, #7 | instr 3 SYSCALL #2.
; Hypothesis: W0 = 2 (instruction count), not 8 (bytes).
MV W0, alvo
MV W1, #0
alvo:
MV W1, #7
SYSCALL #2
