; rt/rt_header_test.asm - F3-03 (#15): rt_header exit-code test
; Compose: cat rt/rt_header.asm rt/rt_header_test.asm > build/rt_header_test.asm
; Pass: exit 10. Fail: exit 60.
;
; Cases
;   word 0 is JUMP with relative offset 54: bytes 30 00 06 C0 (the offset sits
;   at bit 5; instructions are stored big-endian, so compare with LDB)
;   words 1..53 (0x004..0x0D7) are zero
;
; The first instruction below is bound to _start. Reaching it does not prove the
; jump by itself (falling through the placeholders gets here too), so word 0 is
; compared against its encoding.
    ; case 1: word 0 == JUMP +54
    MV W4, #1
    MV W1, #0               ; address
    LDB W2, W1
    MV W0, #0x30
    CMP W2, W0
    BEQ byte_1
    JUMP fail
byte_1:
    ADD W1, W1, W4
    LDB W2, W1
    MV W0, #0x00
    CMP W2, W0
    BEQ byte_2
    JUMP fail
byte_2:
    ADD W1, W1, W4
    LDB W2, W1
    MV W0, #0x06
    CMP W2, W0
    BEQ byte_3
    JUMP fail
byte_3:
    ADD W1, W1, W4
    LDB W2, W1
    MV W0, #0xC0
    CMP W2, W0
    BEQ check_zero
    JUMP fail

check_zero:
    ; case 2: words 1..53 are zero
    MV W1, #0x004           ; address
    MV W3, #0x0D8           ; end, exclusive
    MV W4, #4
    MV W5, #0
zero_loop:
    CMP W1, W3
    BEQ pass
    LOAD W2, W1
    CMP W2, W5
    BEQ zero_next
    JUMP fail
zero_next:
    ADD W1, W1, W4
    JUMP zero_loop

pass:
    MV W8, #10
    SYSCALL #2
fail:
    MV W8, #60
    SYSCALL #2
