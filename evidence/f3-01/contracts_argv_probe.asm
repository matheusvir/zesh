; contracts_argv_probe.asm
; Evidence probe for contracts.md sections 4 and 5.
; Layout: 216-byte rt header at 0x000, code at 0x0D8.
; Parent stages argc/argv at 0x004, forks, child prints the window to the mirror at 0x6000,
; child compares the mirror in-guest and exits 10 (pass) or 60 (fail); parent waits and
; exits 10 only if the collected child status is 10.

JUMP _start
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

_start:
; Stage argc and 3 pointers before SYSCALL #0.
MV W0, #3
STRD W0, #0x004
MV W0, #72
STRD W0, #8
MV W0, #80
STRD W0, #12
MV W0, #88
STRD W0, #16
; Stage NUL-terminated strings in the 128B inline area.
MV W0, #28520
MV W1, #16
SHL W0, W0, W1
MV W1, #25445
OR W0, W0, W1
STRD W0, #72
MV W0, #0
MV W1, #76
STRB W0, W1
MV W0, #27756
MV W1, #16
SHL W0, W0, W1
MV W1, #25960
OR W0, W0, W1
STRD W0, #80
MV W0, #111
MV W1, #84
STRB W0, W1
MV W0, #0
MV W1, #85
STRB W0, W1
MV W0, #27762
MV W1, #16
SHL W0, W0, W1
MV W1, #28535
OR W0, W0, W1
STRD W0, #88
MV W0, #100
MV W1, #92
STRB W0, W1
MV W0, #0
MV W1, #93
STRB W0, W1

; Fork. Parent gets the child PID, child gets -2.
SYSCALL #0
MV W0, #-2
CMP W9, W0
BEQ child

; Parent: touch 0x7230, wait, check collected status.
MV W0, #0
MV W1, #0x7230
STORE W0, W1
OR W8, W1, W1
SYSCALL #1
LDD W0, #0x7230
MV W1, #10
CMP W0, W1
BEQ parent_pass
MV W8, #60
SYSCALL #2
parent_pass:
MV W8, #10
SYSCALL #2

; Child: read argc, walk the pointer array, copy strings to the mirror.
child:
MV W3, #4
MV W4, #0
MV W5, #0x008
MV W6, #0x6000
LDD W7, #0x004
child_arg_loop:
CMP W4, W7
BEQ child_args_done
MV W0, #0
CMP W4, W0
BEQ child_no_space
MV W0, #32
STRB W0, W6
MV W0, #1
ADD W6, W6, W0
child_no_space:
LOAD W8, W5
child_str_loop:
LDB W9, W8
MV W0, #0
CMP W9, W0
BEQ child_str_done
STRB W9, W6
MV W0, #1
ADD W8, W8, W0
ADD W6, W6, W0
JUMP child_str_loop
child_str_done:
ADD W5, W5, W3
MV W0, #1
ADD W4, W4, W0
JUMP child_arg_loop
child_args_done:
MV W0, #10
STRB W0, W6
MV W0, #1
ADD W6, W6, W0
MV W0, #0x6000
SUB W0, W6, W0
STRD W0, #0x6BFC

; In-guest compare of mirror against 'echo hello world\n' (17 bytes).
LDD W0, #24576
MV W1, #28520
MV W2, #16
SHL W1, W1, W2
MV W2, #25445
OR W1, W1, W2
CMP W0, W1
BEQ check_w0_ok
JUMP fail
check_w0_ok:
LDD W0, #24580
MV W1, #27749
MV W2, #16
SHL W1, W1, W2
MV W2, #26656
OR W1, W1, W2
CMP W0, W1
BEQ check_w1_ok
JUMP fail
check_w1_ok:
LDD W0, #24584
MV W1, #30496
MV W2, #16
SHL W1, W1, W2
MV W2, #28524
OR W1, W1, W2
CMP W0, W1
BEQ check_w2_ok
JUMP fail
check_w2_ok:
LDD W0, #24588
MV W1, #25708
MV W2, #16
SHL W1, W1, W2
MV W2, #29295
OR W1, W1, W2
CMP W0, W1
BEQ check_w3_ok
JUMP fail
check_w3_ok:
MV W3, #0x6010
LDB W0, W3
MV W1, #10
CMP W0, W1
BEQ pass
JUMP fail

fail:
MV W8, #60
SYSCALL #2
pass:
MV W8, #10
SYSCALL #2
