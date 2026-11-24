; rt/rt.asm - Front 3 runtime idioms, batch 1 (F3-03, #15)
;
; Routines: rt_memcpy, rt_strcmp, rt_strlen, rt_do_wait.
; Ground truth: zepa-machine e8fd798, contracts.md sections 1.2, 5 and 6.2.
;
; Calling convention (contracts.md 1.2)
;   W8  return link: absolute byte address; every routine returns with JMPR W8
;   W7  argument 1
;   W6  argument 2
;   W5  argument 3
;   W9  return value
;   No register is callee-saved. A routine may clobber W0-W7 and W9; the
;   comment above each routine lists what it clobbers today.
;   The caller must not expect W8 or W9 to survive a call.
;
; Stack (contracts.md 5.1 and 7.1)
;   Region 0x7800..0x7FFB, SP_INIT = 0x7FFC, push pre-decrements SP.
;   Only rt_do_wait uses it. The caller sets SP before the call; SP is
;   unchanged on return. The string routines do not touch SP.
;
; Memory
;   0x7230  wait status slot (frozen, contracts.md 6.2), written by rt_do_wait
;   No other static memory is used.
;
; Assembler and ISA facts these routines rely on
;   - R-Type ALU ops take registers only (no immediates): constants are loaded
;     into scratch registers with MV.
;   - MV does not copy a register; OR Wd, Ws, Ws does.
;   - CMP is unsigned; there is no BNE, so loops exit with BEQ and repeat
;     with JUMP.
;   - LDB zero-extends, so string bytes compare as unsigned.
;   - Labels resolve to relative instruction offsets, never to absolute
;     addresses (contracts.md 5.4). A caller builds the W8 link itself.
;
; Placement
;   Runtime library slot 0x1000..0x17FF in the composed image (contracts.md
;   5.1; composition is F3-15). Until then, tools/rt_link.sh appends this file
;   to the caller's source. The code is position independent and is never
;   reached by fall-through: the caller must exit before the end of its source.

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
