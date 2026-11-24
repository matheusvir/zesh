; rt/do_wait_test.asm - F3-03 (#15): rt_do_wait against real fork/wait/exit
; Link with rt/rt.asm: tools/rt_link.sh rt/do_wait_test.asm
; Child: exit 7. Parent pass: exit 17 (child status + 10, contracts.md 6.1).
; Parent fail: exit 60 (wrong PID or unbalanced SP) or 61 (fork failed).
;
; Run with breakpoints only, never `play`: fork scans every page-table entry
; (contracts.md 9.4). The first exit is the child, the second is the parent.
;
; Test-local call sequence: W8 = absolute byte address of the return label,
; built from img_origin (instruction 0). The formal call/return idiom is F3-04.
img_origin:
    MV SP, #0x7FFC          ; SP_INIT
    SYSCALL #0              ; parent: W9 = child PID; child: W9 = -2
    MV W0, #-2
    CMP W9, W0
    BEQ child
    MV W0, #-1
    CMP W9, W0
    BEQ fork_failed
    STRD W9, #0x6E00        ; save child PID

    MV W0, img_origin
    MV W8, ret_wait
    SUB W8, W8, W0
    MV W0, #1
    ADD W8, W8, W0
    MV W0, #2
    SHL W8, W8, W0
    JUMP rt_do_wait
ret_wait:
    LDD W0, #0x6E00
    CMP W9, W0              ; wait returned the forked child
    BEQ check_sp
    JUMP fail
check_sp:
    MV W0, #0x7FFC
    CMP SP, W0              ; push and pop are balanced
    BEQ collected
    JUMP fail
collected:
    LDD W1, #0x7230         ; child status from the slot
    MV W0, #10
    ADD W8, W1, W0          ; status + 10
    SYSCALL #2

child:
    MV W8, #7
    SYSCALL #2

fail:
    MV W8, #60
    SYSCALL #2
fork_failed:
    MV W8, #61
    SYSCALL #2
