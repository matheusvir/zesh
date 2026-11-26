; rt/rt_header.asm - 216-byte image header (F3-03, #15)
; Layout: contracts.md sections 4.1 and 5.3. Every image begins with this file.
;
; The assembler has no data directive: MV W0, #0 encodes as the word 0x00000000
; and is used as a placeholder. The placeholder words are data, never executed.
; The file ends with the _start label and no instruction after it, so it
; assembles alone to exactly 216 bytes and _start binds to the first
; instruction of the next component (word 54, 0x0D8).

    JUMP _start             ; 0x000: relative offset 54

    ; 0x004: argc
    MV W0, #0

    ; 0x008..0x047: argv[0]..argv[15]
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0

    ; 0x048..0x0C7: argument strings (128 bytes)
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0
    MV W0, #0

    ; 0x0C8: reserved, must be zero
    MV W0, #0

    ; 0x0CC..0x0D7: padding
    MV W0, #0
    MV W0, #0
    MV W0, #0

_start:
