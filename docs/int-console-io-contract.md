# Console I/O contract bridge (Front 1 × Front 3)

**Status: DRAFT — pending Front 1 sign-off.**

| Field | Value |
|---|---|
| Upstream issue | [#48 — \[INT-06\] docs: console I/O contract bridge](https://github.com/matheusvir/zesh/issues/48) |
| Requirements source | [#7 — F3-00 reconnaissance](https://github.com/matheusvir/zesh/issues/7), `docs/f3-00-recon.md` |
| Consumers | [#4 — F3-12 real console swap](https://github.com/matheusvir/zesh/issues/4), [#8 — F3-01 shell contracts](https://github.com/matheusvir/zesh/issues/8) |
| Code basis | `zepa-machine` @ `e8fd798` (`sackOS-paginated`) |
| Technical definition owner | Front 1 — @arthurlazevedo |
| Requirements owner | Front 3 — @matheusvir |
| Reviewer | @KalebeSouza-dev |

This document does not redefine the syscall ABI. The syscall ids `read` = 6 and `write` = 7 are frozen in #8; this bridge only states what the TUI side must provide so those calls have a real console behind them. #8's `contracts.md` remains the normative ABI document.

## 1. Front 3 requirements (frozen)

These six requirements come from the shell arc and are not open for renegotiation. They are the acceptance target for the Front 1 mechanism.

| ID | Requirement |
|---|---|
| R1 | A TUI mechanism delivers a **typed line** to the guest's `read` syscall (id 6, per #8). |
| R2 | Bytes produced by the guest's `write` syscall (id 7, per #8) are displayed in a **readable console surface**, in order, without losing bytes. |
| R3 | **Newline semantics are explicit**: a submitted line reaches the guest with exactly one line terminator, and the terminator is a byte the shell can test. |
| R4 | There is an **EOF syntax**: the operator can signal end-of-input, and a blocked `read` returns 0 rather than hanging. |
| R5 | **Blocking does not freeze the TUI**: when the shell blocks on an empty buffer, the debugger still redraws and accepts console input. |
| R6 | F3-12 gets a **reproducible command sequence** that, once the mechanism lands, a pair can run as-is; it is specified against `zepa-machine @ e8fd798` and re-validated against later revisions. |

R6 is the demo contract; the exact screen contents are asserted by F3-12, not here.

## 2. Current state of the TUI (as of `zepa-machine` @ `e8fd798`)

### 2.1 Surfaces and startup

`tui.go` builds a `tview` app with five read-only panes — **Registers**, **Kernel Variables**, **Memory**, **PCB Vector**, **Page Table** — plus an **Output** text view and a single `cmd>` input field (`tui.go:66-68`). All panes are refreshed by `refreshAll` (`tui.go:95-103`) and by an unconditional 500 ms ticker (`tui.go:348-355`). The VM is started with `debugFlag = true`, so `Boot` only advances when the TUI sends on `StepChan` and waits on `DoneChan` (`machine/zepa.go:584-585, 627-628, 693-699`).

### 2.2 Command surface

All commands are parsed in the one `inputField.SetDoneFunc` handler (`tui.go:152-325`). A bare non-negative integer opens that PID's page table (`tui.go:162-167`). The confirmation surface is the **Output** pane, written only by `appendOutput` (`tui.go:140-148`).

| Command | Behavior | Source |
|---|---|---|
| `d`, `step` [`n`] | Steps 1 or `n` instructions, reports cycles. | `tui.go:170-192` |
| `b`, `breakpoint` `<pc>` | Steps until PC equals the decimal address (or its kernel-mapped alias); reports instructions/cycles. No timeout. | `tui.go:194-228` |
| `c`, `count` | Prints instructions, cycles and cycles/instruction since boot. | `tui.go:230-237` |
| `play` | Steps once per 100 ms until `stop`. | `tui.go:239-262` |
| `stop` | Stops `play`. | `tui.go:264-270` |
| `kill` `<pid>` | Writes the PID into the input buffer and sets the kill flag. | `tui.go:272-286` |
| `input` `<path>` | Assembles the file, loads it into the input buffer, sets the input flag. | `tui.go:288-300` |
| `reg` / `pcb` / `refresh` | Re-reads the Registers / Kernel Variables / all panes. | `tui.go:302-309` |
| `k`, `kernel` / `bitmap`, `bmp` | Opens kernel page table / frame bitmap; Esc or `q` returns. | `tui.go:311-319` |
| `q`, `quit` | Stops the app. | `tui.go:321-323` |

Global key handling is limited to Ctrl+C quitting the app and Esc/`q` closing the page-table overlay (`tui.go:327-346`). There is no other keyboard route into the guest.

### 2.3 The `input` path, precisely

`input <path>` runs the assembler, calls `LoadBuffer`, then `SetInputFlag` (`tui.go:293-300`). `LoadBuffer` writes a 4-byte little-endian length header followed by the image at physical `1 GiB - 65536` (`machine/zepa.go:90, 650-661`). On the next interrupt-enabled instruction, the machine raises `inputInt` (`machine/zepa.go:619-621`). The kernel handler at `sackOS/kernel.asm:353` reads the length word, finds a free PCB slot, initializes a **new process**, copies the buffer as that process's image, and schedules it. The `input` flag is then cleared. This is a one-shot program loader.

### 2.4 Confirmed gap

There is **no path that delivers a typed line to a running guest's `read` syscall**, and no path for guest `write` output to reach the screen:

- `input` always creates a new process from the buffer; it cannot enqueue bytes for an existing process. Running `input` while a shell is alive would load another program, not feed the shell.
- The kernel syscall dispatcher handles only ids 0–4; any other id, including 6 and 7, takes the invalid-syscall path that stores `-1` in the PCB's W9 and reschedules (`sackOS/kernel.asm:747-797`). There is no console read/write implementation yet.
- The **Output** pane is fed only by `appendOutput` from TUI command handlers. Guest output has no surface.
- `play` advances one instruction per 100 ms (`tui.go:246-248`); F3-00 already established this is unusable for boot (~45 h). Any interactive demo needs a faster execution mode (see §4).

The existing `kill` command is the only precedent for TUI→kernel asynchronous delivery: it stages a value in the input buffer and raises a flag (`tui.go:282-286`). It is not reusable for console input because it shares the one-shot input flag with `input`.

## 3. Proposed mechanism (for Front 1 sign-off)

> **PROPOSAL.** Everything in this section is a proposal for Front 1 to accept, amend or reject. It is not frozen ABI. Only §1 is frozen, and only from the Front 3 side.

### 3.1 Options considered

| Option | Sketch | Verdict |
|---|---|---|
| **(i) Dedicated console block + TUI console mode** | A 4 KiB block in kernel-owned physical memory holds an input ring (TUI → kernel) and an output ring (kernel → TUI). A new console interrupt wakes a blocked reader. A TUI mode routes typed lines into the input ring. | **Recommended.** Only option that satisfies R1–R6 without changing `input`. |
| (ii) Prompt/response extension of `input` | `input <path>` then repeated `type <line>` debugger commands that stage one line each. | Cheap, but every line is a debugger command; cannot type while the guest is at a breakpoint, reuses the one-shot load buffer, and has no natural EOF or blocking semantics. Useful only as a scripted fallback. |
| (iii) Scheduled buffered stdin pipe | TUI preloads a script of lines; the machine feeds one line on each `read`. | Deterministic and excellent for regression, but it is not an interactive console and does not remove the need for kernel `read`/`write` plumbing or an output surface. Keep as a test harness, not the demo mechanism. |

Option (i) is recommended. Options (ii) and (iii) remain useful for scripted regressions but do not meet R1/R5/R6 on their own.

### 3.2 Console block (addresses and slots)

The block is one reserved 4 KiB frame, **physical `0x00303000`**, kernel alias **`0xC0303000`**. It sits after the PCB vector, which ends at physical `0x00302074` (`sackOS/abstract_implementation.md` address map: PCB vector at `0x2024`, size `0x300050`), and far below the kernel page table at `0x30007024`. Front 1 must mark the frame used in the bitmap at boot and map it in the kernel page table, so no user process can be allocated it.

| Offset | Size | Slot | Writer → reader |
|---|---|---|---|
| `0x000` | 4 | `CON_IN_HEAD` — monotonic bytes written | TUI → kernel |
| `0x004` | 4 | `CON_IN_TAIL` — monotonic bytes consumed | kernel → TUI |
| `0x008` | 4 | `CON_IN_FLAGS` — bit 0 `EOF`, bit 1 `DATA`, bit 2 `ATTACHED` | TUI → kernel |
| `0x00C` | 4 | reserved (zero) | — |
| `0x010` | 2048 | `CON_IN_BUF` — byte ring, index `counter & 0x7FF` | TUI → kernel |
| `0x810` | 4 | `CON_OUT_HEAD` — monotonic bytes written | kernel → TUI |
| `0x814` | 4 | `CON_OUT_TAIL` — monotonic bytes consumed | TUI → kernel |
| `0x818` | 4 | `CON_OUT_FLAGS` — bit 0 `OVERFLOW` (diagnostic) | kernel → TUI |
| `0x81C` | 4 | reserved (zero) | — |
| `0x820` | 2048 | `CON_OUT_BUF` — byte ring, index `counter & 0x7FF` | kernel → TUI |

Both rings are byte rings with monotonically increasing 32-bit counters and power-of-two capacity. Full condition: `head - tail == 2048`; empty: `head == tail`. Bytes are raw; the kernel performs no line translation.

TUI access must go through a `machine` accessor that takes `m.mu` (the machine's existing mutex) — the TUI must not write the backing array directly while `Boot` may be executing. Front 1 owns that accessor together with the interrupt flag; the TUI only calls `EnqueueConsoleBytes` / `SetConsoleEOF` / `DrainConsoleOutput`.

### 3.3 Newline, EOF and blocking conventions

- **Newline (R3):** the TUI strips the editor's CR and enqueues the line bytes followed by exactly one LF (`0x0A`). No CR is delivered. The shell may treat LF as the only line terminator. A line longer than 1023 bytes is rejected by the TUI with a visible message and is not enqueued.
- **EOF (R4):** Ctrl+D in the TUI is consumed by the TUI; it does **not** enqueue `0x04`. It sets `CON_IN_FLAGS.EOF` after all pending bytes and raises the console wake. A `read` first drains pending bytes; only when the ring is empty and `EOF` is set does it return 0. `EOF` stays set until the TUI enqueues the next line, which clears it. This avoids the ambiguity of using an empty line as EOF (the shell must be able to receive empty lines).
- **Blocking (R5):** when the ring is empty and `EOF` is clear, `read` blocks the calling process on the console (Front 1 chooses/extends the PCB wait state) and schedules away. The TUI never waits on the guest: it keeps its event loop and redraw ticker running. A console wake (TUI enqueues bytes or sets EOF) readies the blocked process. If Front 1 rejects a new block state, the fallback is a non-blocking return with a distinct "would block" result plus a `rele` in the shell loop; that fallback must be stated explicitly because the shell loop changes.
- **Wake (R1/R5):** after updating `CON_IN_HEAD` and flags, the TUI sets a new machine-level console flag, raised alongside the existing `killFlag`/`inputFlag` checks in `machine/zepa.go:611-623`. Front 1 implements the console interrupt handler and is free to name the exception cause. The existing `inputFlag` path must not be reused: it still means "load a new program".
- **Output (R2):** the kernel's `write` appends to `CON_OUT_BUF` and advances `CON_OUT_HEAD`. If the ring is full, the proposed behavior is a **short write** (return the number of bytes copied, possibly 0); the shell retries. `write` must never block the TUI. The TUI drains the ring on each refresh tick and appends the bytes to a scrollable **Console** pane; it advances `CON_OUT_TAIL` only after copying. Bytes are displayed verbatim; escape sequences are not interpreted.

### 3.4 TUI-side console mode

A new debugger command `console` toggles attachment:

- `console on` sets `ATTACHED`, switches the input field's submit target to the guest, and starts a **console pump**: the TUI issues `StepChan` continuously (instead of the 100 ms `play` ticker) while redrawing at a bounded rate (for example every 100 ms). The pump stops on `console off`, on a breakpoint stop, or on `q`.
- `console off` clears `ATTACHED`, stops the pump, and restores the debugger command parser.
- While detached, every existing command behaves exactly as today.

The pump exists because `play` at 100 ms/step cannot execute the kernel/shell path in demo time. It is a TUI scheduling change, not a VM change. Whether it belongs in this bridge or in #24 (Front 2 execution coordination) is an open point (§4).

### 3.5 Reproducible demo sequence (proposed target for F3-12)

Run from `zepa-machine/`:

```text
go run -tags kernel . 2GB 128
input shell_loop.asm
b 0
console on
help
echo hello world
pid
true
false
wc
one two
three
<Ctrl+D>
bogus
exit
```

Expected, for the F3-12 evidence run:

- `console on` reports attachment and the pump starts; the panel stays responsive.
- `echo hello world` produces exactly `hello world\n` on the Console pane.
- `wc` consumes the two lines and returns its counts when Ctrl+D is pressed; the shell does not hang.
- `bogus` produces the shell's error message and returns to the prompt.
- `exit` terminates the shell; no fault is reported in the PCB Vector at any point.

Exit-status capture is deliberately not in this sequence. Arming `b 4036` while the console pump is running is an execution-coordination problem (the current `b` is itself a foreground step-run, so issuing it before `exit` would step a blocked shell forever, and issuing it after `exit` races cleanup). F3-12 must capture status 0 through whatever armed-breakpoint/run mechanism #24 delivers, or via its harness; see §4 item 4. This sequence proves R1–R5 and the console transcript for R6, not the exit code.

The sequence depends on the proposed `console on|off` commands and on the pump. It is not runnable against `e8fd798` as-is; it becomes runnable when Front 1 delivers §3.2–3.3 and Front 3 delivers §3.4. F3-12 owns the final byte-for-byte assertions and the status-capture harness.

### 3.6 Ownership split

| Side | Owns |
|---|---|
| **Front 1** (@arthurlazevedo) | Kernel `read`/`write` implementations per #8; reservation and mapping of `0x00303000`; `CON_*` layout; console interrupt, blocked-reader state and wake; output ring producer and short-write behavior; the `machine` accessor and console flag. |
| **Front 3** (@matheusvir) | Shell read loop, LF/EOF handling and short-write retry; TUI console pane, `console on|off` routing and pump; the demo script and its evidence log. |
| **Front 2** (for awareness) | #24 execution coordination may own or replace the console pump; no console-block layout changes expected. |

## 4. What is NOT decided here

The following are deliberately left open. None of them may be invented by an implementer without a Front 1/Front 3 decision recorded on #48 or in #8.

1. **Blocking on boot / before attach.** What `read` does if a console client is not attached, and whether `read` blocks forever, returns EOF, or faults when no console session exists. The proposal assumes the shell is attached before it reads.
2. **TUI focus management and key routing.** How the operator switches between the debugger field and the console field; what Esc does while attached; whether debugger commands remain available via a prefix while attached; how the page-table overlay interacts with console mode. The demo sequence assumes a mode toggle, not a focus policy.
3. **Escape sequences.** Arrow keys, Ctrl+C (today it quits the whole TUI, `tui.go:328-331`), Ctrl+Z, backspace and any other control byte. The current proposal only freezes LF, CR stripping and Ctrl+D-as-EOF. In particular, guest interrupt versus debugger quit is unresolved.
4. **Execution pacing and breakpoints during console mode.** Whether the console pump belongs to this bridge, to #24, or to a new TUI run mode; how breakpoints and single-step interact with the pump; how a breakpoint is armed **without** running the guest synchronously (the current `b` steps in a goroutine until the PC matches, which cannot be combined with a shell blocked in `read`), and the redraw rate. Without a decision, R6 proves the console transcript but not the exit status at `b 4036`.
5. **Console ownership with multiple processes.** Which PID owns the console after `fork`, what a child inherits, and what happens if two processes read concurrently. The shell demo is single-reader; a general answer is out of scope.
6. **Output-ring back-pressure.** The proposal recommends short writes, but Front 1 must confirm that `write` cannot block the TUI and must state whether a zero-byte short write is allowed. Scrollback size and whether pre-attach output is buffered are also open.
7. **Interrupt cause numbering.** Front 1 owns the choice of exception cause for the console wake and must publish it in #8/zepa-machine docs. This bridge intentionally does not assign a number.
8. **Reset/teardown.** Whether `console off` flushes or discards unread guest input, and how a new `input` interacts with a stale console block.

## 5. Sign-off

| Role | Person | Scope | State |
|---|---|---|---|
| Front 1 lead — technical definition | @arthurlazevedo | Accepts/amends §3.2–3.3, owns kernel console plumbing and the interrupt/blocking model | **PENDING** |
| Front 3 lead — requirements frozen | @matheusvir | Confirms §1 is complete and unchanged, owns shell loop and TUI console mode | **PENDING** |
| Reviewer | @KalebeSouza-dev | Cross-front review of the contract and the demo sequence | **PENDING** |

Sign-off means commenting on [#48](https://github.com/matheusvir/zesh/issues/48) with either "accept as proposed", or the exact amendments. Once Front 1 accepts, this document's status changes to `SIGNED` and the frozen details move into #8's `contracts.md`; this file then remains the bridge record and demo reference.
