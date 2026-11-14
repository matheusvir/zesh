; F3-02 Q-A2: backward label as MV immediate (no #).
; Layout: instr 0 base: MV W1, #7 | instr 1 MV W0, base | instr 2 SYSCALL #2.
; Hypothesis: W0 = -1, observed as 0xFFFFFFFF (sign-extended).
base:
MV W1, #7
MV W0, base
SYSCALL #2
