; F3-02 Q-C1: no _start anywhere; entry must be the first instruction (VA 0).
; Layout: instr 0 MV W1, #5 | instr 1 SYSCALL #2 (8 bytes).
; Hypothesis: assembles; b 0 stops at pc=0; after d 1: W1=5, pc=4; exit status 0.
MV W1, #5
SYSCALL #2
