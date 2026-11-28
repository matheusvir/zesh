; rt/strcmp_test.asm - F3-03 (#15): rt_strcmp exit-code test
; Link with rt/rt.asm: tools/rt_link.sh rt/strcmp_test.asm
; Pass: exit 10. Fail: exit 60.
;
; Strings
;   A = "abc" at 0x6E00
;   B = "abc" at 0x6E10
;   C = "abd" at 0x6E20
;   D = "ab"  at 0x6E30
; Cases (expected W9 is exact, compared in-guest)
;   strcmp(A, B) ==   0     equal
;   strcmp(A, C) ==  -1     'c' - 'd'
;   strcmp(C, A) ==   1     'd' - 'c'
;   strcmp(D, A) == -99     NUL - 'c' (shorter string sorts first)
;
; Test-local call sequence: W8 = absolute byte address of the return label,
; built from img_origin (instruction 0). The formal call/return idiom is F3-04.
img_origin:
    MV W1, #1
    MV W3, #97              ; 'a'
    MV W4, #98              ; 'b'
    MV W5, #99              ; 'c'
    MV W6, #100             ; 'd'
    MV W0, #0               ; NUL
    ; A = "abc"
    MV W2, #0x6E00
    STRB W3, W2
    ADD W2, W2, W1
    STRB W4, W2
    ADD W2, W2, W1
    STRB W5, W2
    ADD W2, W2, W1
    STRB W0, W2
    ; B = "abc"
    MV W2, #0x6E10
    STRB W3, W2
    ADD W2, W2, W1
    STRB W4, W2
    ADD W2, W2, W1
    STRB W5, W2
    ADD W2, W2, W1
    STRB W0, W2
    ; C = "abd"
    MV W2, #0x6E20
    STRB W3, W2
    ADD W2, W2, W1
    STRB W4, W2
    ADD W2, W2, W1
    STRB W6, W2
    ADD W2, W2, W1
    STRB W0, W2
    ; D = "ab"
    MV W2, #0x6E30
    STRB W3, W2
    ADD W2, W2, W1
    STRB W4, W2
    ADD W2, W2, W1
    STRB W0, W2

    ; case 1: strcmp(A, B) == 0
    MV W0, img_origin
    MV W8, ret_eq
    SUB W8, W8, W0
    MV W0, #1
    ADD W8, W8, W0
    MV W0, #2
    SHL W8, W8, W0
    MV W7, #0x6E00
    MV W6, #0x6E10
    JUMP rt_strcmp
ret_eq:
    MV W0, #0
    CMP W9, W0
    BEQ case_lt
    JUMP fail

case_lt:
    ; case 2: strcmp(A, C) == -1
    MV W0, img_origin
    MV W8, ret_lt
    SUB W8, W8, W0
    MV W0, #1
    ADD W8, W8, W0
    MV W0, #2
    SHL W8, W8, W0
    MV W7, #0x6E00
    MV W6, #0x6E20
    JUMP rt_strcmp
ret_lt:
    MV W0, #-1
    CMP W9, W0
    BEQ case_gt
    JUMP fail

case_gt:
    ; case 3: strcmp(C, A) == 1
    MV W0, img_origin
    MV W8, ret_gt
    SUB W8, W8, W0
    MV W0, #1
    ADD W8, W8, W0
    MV W0, #2
    SHL W8, W8, W0
    MV W7, #0x6E20
    MV W6, #0x6E00
    JUMP rt_strcmp
ret_gt:
    MV W0, #1
    CMP W9, W0
    BEQ case_prefix
    JUMP fail

case_prefix:
    ; case 4: strcmp(D, A) == -99
    MV W0, img_origin
    MV W8, ret_prefix
    SUB W8, W8, W0
    MV W0, #1
    ADD W8, W8, W0
    MV W0, #2
    SHL W8, W8, W0
    MV W7, #0x6E30
    MV W6, #0x6E00
    JUMP rt_strcmp
ret_prefix:
    MV W0, #-99
    CMP W9, W0
    BEQ pass
    JUMP fail

pass:
    MV W8, #10
    SYSCALL #2
fail:
    MV W8, #60
    SYSCALL #2
