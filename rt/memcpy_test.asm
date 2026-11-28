; rt/memcpy_test.asm - F3-03 (#15): rt_memcpy exit-code test
; Link with rt/rt.asm: tools/rt_link.sh rt/memcpy_test.asm
; Pass: exit 10. Fail: exit 60.
;
; Layout
;   src = "zepa!" at 0x6E00 (bytes 0x7A 0x65 0x70 0x61 0x21)
;   dst = 0x6E40, pre-filled with sentinel 0x55 in bytes 0..7
; Cases
;   1. memcpy(dst, src, 0): returns dst, dst[0] still 0x55
;   2. memcpy(dst, src, 5): returns dst, word dst[0..3] == 0x6170657A,
;      dst[4] == 0x21, dst[5] == 0x55 (no overrun)
;
; Test-local call sequence: W8 = absolute byte address of the return label,
; built from img_origin (instruction 0). The formal call/return idiom is F3-04.
img_origin:
    MV W1, #1
    ; src = "zepa!"
    MV W2, #0x6E00
    MV W0, #122             ; 'z'
    STRB W0, W2
    ADD W2, W2, W1
    MV W0, #101             ; 'e'
    STRB W0, W2
    ADD W2, W2, W1
    MV W0, #112             ; 'p'
    STRB W0, W2
    ADD W2, W2, W1
    MV W0, #97              ; 'a'
    STRB W0, W2
    ADD W2, W2, W1
    MV W0, #33              ; '!'
    STRB W0, W2
    ; dst sentinel: two words of 0x55 bytes
    MV W0, #0x5555
    MV W3, #16
    SHL W4, W0, W3
    OR W0, W0, W4           ; W0 = 0x55555555
    STRD W0, #0x6E40
    STRD W0, #0x6E44

    ; case 1: n = 0 copies nothing
    MV W0, img_origin
    MV W8, ret_zero
    SUB W8, W8, W0
    MV W0, #1
    ADD W8, W8, W0
    MV W0, #2
    SHL W8, W8, W0
    MV W7, #0x6E40
    MV W6, #0x6E00
    MV W5, #0
    JUMP rt_memcpy
ret_zero:
    MV W0, #0x6E40
    CMP W9, W0
    BEQ zero_ret_ok
    JUMP fail
zero_ret_ok:
    MV W2, #0x6E40
    LDB W3, W2
    MV W0, #0x55
    CMP W3, W0
    BEQ case_five
    JUMP fail

case_five:
    ; case 2: n = 5
    MV W0, img_origin
    MV W8, ret_five
    SUB W8, W8, W0
    MV W0, #1
    ADD W8, W8, W0
    MV W0, #2
    SHL W8, W8, W0
    MV W7, #0x6E40
    MV W6, #0x6E00
    MV W5, #5
    JUMP rt_memcpy
ret_five:
    MV W0, #0x6E40
    CMP W9, W0
    BEQ five_ret_ok
    JUMP fail
five_ret_ok:
    ; word dst[0..3] == 0x6170657A ("zepa", little-endian)
    MV W0, #0x6170
    MV W3, #16
    SHL W0, W0, W3
    MV W4, #0x657A
    OR W0, W0, W4
    LDD W2, #0x6E40
    CMP W2, W0
    BEQ word_ok
    JUMP fail
word_ok:
    ; dst[4] == '!'
    MV W1, #0x6E44
    LDB W3, W1
    MV W0, #33
    CMP W3, W0
    BEQ bang_ok
    JUMP fail
bang_ok:
    ; dst[5] == 0x55 (no overrun)
    MV W1, #0x6E45
    LDB W3, W1
    MV W0, #0x55
    CMP W3, W0
    BEQ pass
    JUMP fail

pass:
    MV W8, #10
    SYSCALL #2
fail:
    MV W8, #60
    SYSCALL #2
