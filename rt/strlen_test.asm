; rt/strlen_test.asm - F3-03 (#15): rt_strlen exit-code test
; Link with rt/rt.asm: tools/rt_link.sh rt/strlen_test.asm
; Pass: exit 10. Fail: exit 60.
;
; Cases
;   "hello" at 0x6E00 -> 5
;   ""      at 0x6E10 -> 0
;
; Test-local call sequence: W8 = absolute byte address of the return label,
; built from img_origin (instruction 0). The formal call/return idiom is F3-04.
img_origin:
    ; "hello\0" at 0x6E00
    MV W1, #1
    MV W2, #0x6E00
    MV W0, #104             ; 'h'
    STRB W0, W2
    ADD W2, W2, W1
    MV W0, #101             ; 'e'
    STRB W0, W2
    ADD W2, W2, W1
    MV W0, #108             ; 'l'
    STRB W0, W2
    ADD W2, W2, W1
    STRB W0, W2             ; 'l'
    ADD W2, W2, W1
    MV W0, #111             ; 'o'
    STRB W0, W2
    ADD W2, W2, W1
    MV W0, #0
    STRB W0, W2             ; NUL
    ; "\0" at 0x6E10
    MV W2, #0x6E10
    STRB W0, W2

    ; case 1: strlen("hello") == 5
    MV W0, img_origin
    MV W8, ret_hello
    SUB W8, W8, W0
    MV W0, #1
    ADD W8, W8, W0
    MV W0, #2
    SHL W8, W8, W0
    MV W7, #0x6E00
    JUMP rt_strlen
ret_hello:
    MV W0, #5
    CMP W9, W0
    BEQ case_empty
    JUMP fail

case_empty:
    ; case 2: strlen("") == 0
    MV W0, img_origin
    MV W8, ret_empty
    SUB W8, W8, W0
    MV W0, #1
    ADD W8, W8, W0
    MV W0, #2
    SHL W8, W8, W0
    MV W7, #0x6E10
    JUMP rt_strlen
ret_empty:
    MV W0, #0
    CMP W9, W0
    BEQ pass
    JUMP fail

pass:
    MV W8, #10
    SYSCALL #2
fail:
    MV W8, #60
    SYSCALL #2
