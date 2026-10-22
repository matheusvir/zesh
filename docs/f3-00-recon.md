# F3-00: TUI adequacy reconnaissance

Issue: [#7](https://github.com/matheusvir/zesh/issues/7). Objective: verify the TUI debugger's adequacy for shell development through its `input` path.

## Environment and boot

Machine version: `sackOS-paginated`, commit `e8fd798`. From `zepa-machine/`, start a fresh machine:

```bash
go run -tags kernel . 2GB 128
```

At the TUI `cmd>` prompt, run:

```text
b 300
```

Observed: `Breakpoint reached at pc=300 after 1613892 instructions`, `Cycles used: 2170970`, CPU PC `0xC000012C`, `running_pid = idle`, and an empty **PCB Vector**. Run the three samples below in order in this session, waiting for each breakpoint to finish before entering the next command.

Breakpoints use decimal addresses and also match the corresponding kernel-mapped address. The addresses below apply to this machine version:

| Command | Stop point |
|---|---|
| `b 300` | Kernel boot complete, at `0xC000012C`. |
| `b 0` | Loaded program's entry, before its first instruction. |
| `b 4036` | `0xC0000FC4`, immediately after `exit` stores the status in the process PCB's W9, before process cleanup. |
| `b 5536` | Kernel idle loop at `0xC00015A0`, after process cleanup. |

The **PCB Vector** pane is the process table and refreshes automatically from the 500 ms ticker, so no command is needed to see it. The `pcb` command refreshes a different pane, **Kernel Variables** (`tui.go:305`); a `refresh` command redraws all panes immediately but is not required for observations. A breakpoint has no timeout (`tui.go:194-225`): if its address is never hit, `b` spins forever and quitting the TUI is the only exit.

## Gap matrix

| Need | Available and observed | Gap or limit |
|---|---|---|
| Program input | `input <path>` assembled all three samples and created runnable processes; `b 0` stopped at their entry. | `input sent` confirms submission, not execution completion. No typed-line input path for a running shell was identified in `tui.go`. `read` and `write` are not yet part of the kernel ABI: `sackOS/specs.md` defines syscall IDs 0–4 only, and `read`=6/`write`=7 are current F3-01 proposals (#8) — this is exactly why the interactive no-go is not a TUI-only problem. |
| Run and pause | `play` started execution; `stop` paused it. `b <pc>` ran to a chosen instruction and reported instructions/cycles used. | `play` is not merely slow: at 100 ms per instruction, boot's 1.6M instructions would take roughly 45 h, so treat `play` as unusable for boot and long kernel paths and use breakpoints instead. |
| Step | `d 2`, `d 3`, and `d 1` produced the expected PC/register changes. | A step may execute kernel code during an interrupt; select user-code breakpoints before checking user registers. |
| Registers and memory | `reg` displayed live CPU registers; Memory showed instructions around the PC; `1` opened the child's page table. | The memory pane is PC-centered; arbitrary buffer-byte inspection was not demonstrated. |
| PCB and exit status | The **PCB Vector** pane showed PID, parent, flags, pages and saved registers. `b 4036` exposed exit status 0 in PCB W9 for both terminating samples. | These parentless processes are removed during cleanup; capture the status before removal. Saved PCB registers need not match the live CPU registers until context is saved. |

## Sample runs

### `asm/samples/small.asm`

```text
input asm/samples/small.asm
b 0
d 2
reg
b 4036
reg
b 5536
```

Observed:

- `input sent (12 bytes)`; entry reached after 110210 instructions, with PID 0 running and one mapped page.
- After `d 2`: CPU PC = 8, W1 = 5, `running_pid = 0`; the next instruction was `SYSCALL #2`.
- `b 4036` took 110 instructions. The **PCB Vector** pane showed PID 0 with W1 = 5, saved PC = 12, W8 = 0 and W9 = 0: the kernel had recorded exit status 0.
- `b 5536` took 5521 instructions and reached idle with an empty **PCB Vector**.

### `asm/samples/syscall.asm`

```text
input asm/samples/syscall.asm
b 0
b 4036
b 5536
```

Observed: `input sent (4 bytes)`; entry reached after 110206 instructions. The sample's only instruction is `SYSCALL #2`. After another 110 instructions, `b 4036` stopped with **PCB Vector** PID 0 at saved PC = 4, W8 = 0 and W9 = 0, confirming status 0 was recorded. Process cleanup precedes the next sample.

### `asm/samples/fork.asm`

```text
input asm/samples/fork.asm
b 0
b 20
reg
d 3
reg
play
stop
1
```

Allow `play` to run for a few seconds before `stop`. After inspecting the page table, press Esc to return to the command prompt, then run:

```text
b 28
d 1
reg
```

Observed:

- `input sent (44 bytes)`; entry reached after 110226 instructions.
- `b 20` reached the instruction after `fork` after 11122300 instructions (15100925 cycles). PID 1 was running with CPU PC = 20 and W9 = -2. The PC was back in user code and the fork had completed.

| **PCB Vector** snapshot after fork | Parent | Flags | Pages | Saved W9 | Saved PC |
|---|---|---|---|---|---|
| PID 0 (parent) | -1 | `M..Y` (ready) | 1 | 1 (child PID) | 20 |
| PID 1 (child) | 0 | `M..R` (running) | 1 | -2 | 20 |

- After `d 3`, the child had CPU W1 = 1 and PC = 40, demonstrating its own counter loop.
- Output showed `play started (100ms/step)` and `play stopped`; the live child counter advanced to W1 = 50 in the captured run. This value depends on how long `play` runs.
- Command `1` displayed the child's page table: page 0, virtual address `0x00000000`, frame `0x40001`, PTE `0x00140001`.
- `b 28` reached the parent's counter instruction after a clock-driven context switch. After `d 1`, PID 0 was running with CPU W0 = 1, W9 = 1 and PC = 32. PID 1 was ready, with saved W1 = 8120 and PC = 40 in the captured run.
- This sample intentionally loops in both processes; it does not exercise process exit.

## Decision and Front 1 question

**Go for shell development through the TUI `input` path** using canned input/stubs, breakpoints, stepping, and register/PCB Vector inspection. All three samples ran; exit status was captured for `small.asm` and `syscall.asm`, and the fork return values, parent/child relationship, counter loops and scheduling were observed.

Known limits: `play` at 100 ms/step is unusable for long kernel paths (boot alone is ~45 h); breakpoints depend on the code layout of the tested version; exit status must be captured before PCB cleanup; arbitrary buffer-byte inspection still needs verification before relying on it for shell output assertions.

**No-go for an interactive shell demo through the current command field until the console-input/output mechanism is specified and integrated.** This does not block development on canned fixtures. Assembler capability questions remain in F3-02.

Front 1: What TUI action, buffer, or event delivers a typed line to a running shell's `read` syscall? Where is `write` output displayed, and what are the newline, EOF, and blocking semantics? The answer needs a reproducible command sequence for the later real-console demo.
