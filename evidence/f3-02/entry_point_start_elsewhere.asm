; F3-02 Q-C2: control with _start away from the top.
; Layout: instr 0 JUMP _start | instr 1 MV W1, #99 (skipped) | instr 2 _start: MV W1, #5 | instr 3 SYSCALL #2.
; Hypothesis: _start is an ordinary label; the explicit JUMP lands on instr 2
; (pc=8 after 1 step) and the skipped MV never runs; final W1=5, exit status 0.
JUMP _start
MV W1, #99
_start:
MV W1, #5
SYSCALL #2
