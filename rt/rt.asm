; rt/rt.asm - Front 3 runtime idioms, batch 1 (F3-03, #15)
; Internal call convention: contracts.md section 1.2.

; rt_memcpy - copy W5 bytes from W6 to W7, forward, byte by byte
;   in:  W7 = dst, W6 = src, W5 = n (unsigned; 0 copies nothing)
;   out: W9 = dst
;   Regions must not overlap. Clobbers W1-W7, W9. Leaf, no syscall.
rt_memcpy:
    OR W9, W7, W7           ; return value = dst
    MV W1, #1
    MV W2, #0
rt_memcpy_loop:
    CMP W5, W2
    BEQ rt_memcpy_done      ; n == 0
    LDB W3, W6
    STRB W3, W7
    ADD W7, W7, W1
    ADD W6, W6, W1
    SUB W5, W5, W1
    JUMP rt_memcpy_loop
rt_memcpy_done:
    JMPR W8

; rt_strcmp - compare two NUL-terminated byte strings
;   in:  W7 = a, W6 = b
;   out: W9 = 0 when equal, else a[i] - b[i] at the first differing byte
;        (bytes are unsigned, so the sign follows C strcmp)
;   Clobbers W1-W4, W6, W7, W9. Leaf, no syscall.
rt_strcmp:
    MV W1, #1
    MV W2, #0
rt_strcmp_loop:
    LDB W3, W7
    LDB W4, W6
    CMP W3, W4
    BEQ rt_strcmp_same
    SUB W9, W3, W4          ; first difference
    JMPR W8
rt_strcmp_same:
    CMP W3, W2
    BEQ rt_strcmp_equal     ; both strings ended together
    ADD W7, W7, W1
    ADD W6, W6, W1
    JUMP rt_strcmp_loop
rt_strcmp_equal:
    MV W9, #0
    JMPR W8

; rt_strlen - length of a NUL-terminated byte string
;   in:  W7 = s
;   out: W9 = number of bytes before the NUL
;   Clobbers W0-W2, W7, W9. Leaf, no syscall.
rt_strlen:
    MV W9, #0
    MV W1, #1
    MV W2, #0
rt_strlen_loop:
    LDB W0, W7
    CMP W0, W2
    BEQ rt_strlen_done
    ADD W9, W9, W1
    ADD W7, W7, W1
    JUMP rt_strlen_loop
rt_strlen_done:
    JMPR W8

; rt_do_wait - wait for a child through the touch idiom (contracts.md 6.2)
;   in:  nothing; SP must point into the stack region (SP_INIT = 0x7FFC)
;   out: W9 = child PID, or -1 when there are no children
;        child status word at 0x7230 (valid only when W9 is a PID)
;   SYSCALL takes the slot in W8, so the link is spilled to the stack.
;   Uses 4 bytes of stack. Clobbers W1, W9. Syscall: wait (1).
rt_do_wait:
    MV W1, #4
    SUB SP, SP, W1
    STORE W8, SP            ; push link
    MV W1, #0x7230
    STORE W0, W1            ; touch: maps the slot page (value irrelevant)
    OR W8, W1, W1           ; W8 = status slot address
    SYSCALL #1
    LOAD W8, SP             ; pop link
    MV W1, #4
    ADD SP, SP, W1
    JMPR W8
