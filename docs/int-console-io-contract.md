# Console I/O contract bridge (Front 1 × Front 3)

**Status: SIGNED**

| Field | Value |
|---|---|
| Upstream issue | [#48 — \[INT-06\] docs: console I/O contract bridge](https://github.com/matheusvir/zesh/issues/48) |
| Requirements source | [#7 — F3-00 reconnaissance](https://github.com/matheusvir/zesh/issues/7), `docs/f3-00-recon.md` |
| Consumers | [#4 — F3-12 real console swap](https://github.com/matheusvir/zesh/issues/4), [#8 — F3-01 shell contracts](https://github.com/matheusvir/zesh/issues/8) |
| Code basis | `zepa-machine` @ `e8fd798` (`sackOS-paginated`) |
| Technical definition owner | Front 1 — @RenanAF18 |
| Requirements owner | Front 3 — @matheusvir (global lead) |
| Reviewer | @carlosarthurns |
| Implementing tasks | [#55 — F1-03 console frame](https://github.com/matheusvir/zesh/issues/55), [#58 — F1-06 `read`](https://github.com/matheusvir/zesh/issues/58), [#59 — F1-07 `write`](https://github.com/matheusvir/zesh/issues/59), [#60 — F1-08 TUI console](https://github.com/matheusvir/zesh/issues/60) |
| Executable demo | [#64 — F1-12 Front 1 evidence](https://github.com/matheusvir/zesh/issues/64), [#4 — F3-12 byte-for-byte assertions](https://github.com/matheusvir/zesh/issues/4) |

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

## 3. Signed mechanism

> **SIGNED.** Front 1 accepted this section with the four #48 amendments: frame (§3.2), `write` (§3.3), `read` (§3.3) and ownership (§3.6). It is the console bridge, not syscall ABI: `contracts.md` stays normative for ids 6 and 7, the buffer encoding and `MAX_XFER`. Items in §4 remain open.

### 3.1 Options considered

| Option | Sketch | Verdict |
|---|---|---|
| **(i) Dedicated console block + TUI console mode** | A 4 KiB block in kernel-owned physical memory holds an input ring (TUI → kernel) and an output ring (kernel → TUI). A new console interrupt wakes a blocked reader. A TUI mode routes typed lines into the input ring. | **Recommended.** Only option that satisfies R1–R6 without changing `input`. |
| (ii) Prompt/response extension of `input` | `input <path>` then repeated `type <line>` debugger commands that stage one line each. | Cheap, but every line is a debugger command; cannot type while the guest is at a breakpoint, reuses the one-shot load buffer, and has no natural EOF or blocking semantics. Useful only as a scripted fallback. |
| (iii) Scheduled buffered stdin pipe | TUI preloads a script of lines; the machine feeds one line on each `read`. | Deterministic and excellent for regression, but it is not an interactive console and does not remove the need for kernel `read`/`write` plumbing or an output surface. Keep as a test harness, not the demo mechanism. |

Option (i) is recommended. Options (ii) and (iii) remain useful for scripted regressions but do not meet R1/R5/R6 on their own.

### 3.2 Console block (addresses and slots)

#### Frame

The block is one reserved 4 KiB frame at **physical `0x3012A000`**, range **`[0x3012A000, 0x3012B000)`**.

- **Kernel alias.** The canonical contract label is **`0xC03012A000`**. Under the current kernel mapping rule (kernel VA = physical + `0xC0000000`) the mapped kernel VA is **`0xF012A000`** (`0x3012A000 + 0xC0000000`). F1-03 implements the arithmetic form.
- **Bitmap-adjacency rule.** The frame is the first 4 KiB-aligned frame after Front 2's F2-01 frame bitmap `[0x30109024, 0x30129024)`: the bitmap ends at `0x30129024`, and the next multiple of `0x1000` is `0x3012A000`. Moving the frame, or growing the bitmap into `0x3012A000`, needs a new contract.
- **Ownership.** F1-03 (#55) owns the reservation: marking the frame used in the frame bitmap at boot, before the first schedule; guaranteeing the kernel mapping; and zeroing the six header words below. No user or kernel allocation may receive this frame.

#### Non-overlap with F2-01 regions

The frame must not overlap any F2-01 physical region. At the signed layout it is disjoint from all of them:

| F2-01 region | Physical range | Relation to `[0x3012A000, 0x3012B000)` |
|---|---|---|
| Code | `[0x00000000, 0x00004000)` | Below |
| Constants / variables | `[0x00004000, 0x00004024)` | Below |
| PCB vector, 256 × `0x300050`, including every per-PCB page table | `[0x00004024, 0x30009024)` | Below |
| KPTR (kernel page table, 1 MiB) | `[0x30009024, 0x30109024)` | Below |
| Frame bitmap | `[0x30109024, 0x30129024)` | Below; gap `[0x30129024, 0x3012A000)` is alignment padding |
| Stack | `[0x3FFC0000, 0x3FFD0000)` | Above |
| Control | `[0x3FFD0000, 0x3FFE0000)` | Above |
| Image | `[0x3FFE0000, 0x3FFF0000)` | Above |
| Buffer | `[0x3FFF0000, 0x40000000)` | Above |

**Superseded address.** The draft's `0x00303000` (alias `0xC0303000`) is not reusable. It lies inside the PCB vector: at `zepa-machine @ e8fd798` (vector at `0x2024`) it falls inside PCB 1's 3 MiB page table `[0x003020C4, 0x006020C4)`, and under the F2-01 layout (vector at `0x4024`) it falls inside PCB 0's page table `[0x00004074, 0x00304074)`. A console ring there would corrupt a process's address space. This is `F1-CR-4` in `contracts.md` §10.2.

#### Layout

| Offset | Size | Slot | Writer → reader |
|---|---|---|---|
| `0x000` | 4 | `CON_IN_HEAD` — monotonic bytes written | TUI → kernel |
| `0x004` | 4 | `CON_IN_TAIL` — monotonic bytes consumed | kernel → TUI |
| `0x008` | 4 | `CON_IN_FLAGS` — bit 0 `EOF`, bit 1 `DATA`, bit 2 `ATTACHED` | TUI → kernel |
| `0x00C` | 4 | reserved (zero) | — |
| `0x010` | 1024 | `CON_IN_BUF` — byte ring `[0x010, 0x410)`, index `counter & 0x3FF` | TUI → kernel |
| `0x410` | 4 | `CON_OUT_HEAD` — monotonic bytes written | kernel → TUI |
| `0x414` | 4 | `CON_OUT_TAIL` — monotonic bytes consumed | TUI → kernel |
| `0x418` | 4 | `CON_OUT_FLAGS` — bit 0 `OVERFLOW` (diagnostic) | kernel → TUI |
| `0x41C` | 4 | reserved (zero) | — |
| `0x420` | 1024 | `CON_OUT_BUF` — byte ring `[0x420, 0x820)`, index `counter & 0x3FF` | kernel → TUI |
| `0x820` | 2016 | unused, `[0x820, 0x1000)`; no `CON_*` slot may be placed here without a new contract | — |

Both rings are byte rings with monotonically increasing 32-bit counters and power-of-two capacity 1024. Full condition: `head - tail == 1024`; empty: `head == tail`. Bytes are raw; the kernel performs no line translation. At boot the six header words (`CON_IN_HEAD`, `CON_IN_TAIL`, `CON_IN_FLAGS`, `CON_OUT_HEAD`, `CON_OUT_TAIL`, `CON_OUT_FLAGS`) are zero, so both rings read as empty; the ring bytes need not be zeroed.

**Feasibility.** The last ring byte is at offset `0x81F` (physical `0x3012A81F`), so the whole layout fits in `[0x3012A000, 0x3012B000)` and no offset reaches `0x1000`. The draft's two 2048-byte rings did not fit: `CON_OUT_BUF` at `0x820` plus 2048 bytes ends at `0x1020`, 32 bytes past the frame. Option (a) of the #48 feasibility gate is therefore signed: two 1024-byte rings in the fixed 4 KiB frame. This matches `contracts.md` §3.2 ("two 1024-byte rings") and the TUI's 1023-byte line limit (§3.3): a maximal line plus its LF is exactly 1024 bytes and fits an empty input ring. F1-03 and F1-05 consume this layout.

TUI access must go through a `machine` accessor that takes `m.mu` (the machine's existing mutex) — the TUI must not write the backing array directly while `Boot` may be executing. Front 1 owns that accessor together with the interrupt flag; the TUI only calls `EnqueueConsoleBytes` / `SetConsoleEOF` / `DrainConsoleOutput`.

### 3.3 Newline, EOF, blocking, `read` and `write` conventions

This section states how the console block backs `read` (6) and `write` (7). The buffer encoding, `MAX_XFER = 512` and the return classes stay normative in `contracts.md` §3.1–3.2; nothing here widens them.

- **Newline (R3):** the TUI strips the editor's CR and enqueues the line bytes followed by exactly one LF (`0x0A`). No CR is delivered. The shell may treat LF as the only line terminator. A line longer than 1023 bytes is rejected by the TUI with a visible message and is not enqueued; the limit is the 1024-byte input ring signed in §3.2 (#48 feasibility gate, implemented by F1-05, #57) minus the LF. A line and its LF are enqueued in one accessor call. If the input ring does not have room for all of them, nothing is enqueued: the TUI shows `console input buffer full` in the Console pane and keeps the text for retry (F1-08, #60). "Full" therefore means "no room for the whole line plus its LF", and the kernel never observes half of a submitted line. Front 1 confirmed this rule on [#48](https://github.com/matheusvir/zesh/issues/48#issuecomment-7225370504).
- **EOF (R4):** Ctrl+D in the TUI is consumed by the TUI; it does **not** enqueue `0x04`. It sets `CON_IN_FLAGS.EOF` after all pending bytes and raises the console wake. A `read` first drains pending bytes; only when the ring is empty and `EOF` is set does it return 0. `EOF` stays set until the TUI enqueues the next line, which clears it. This avoids the ambiguity of using an empty line as EOF (the shell must be able to receive empty lines).
- **Blocking (R5):** when the ring is empty and `EOF` is clear, `read` blocks the calling process on the console (Front 1 chooses/extends the PCB wait state) and schedules away. The TUI never waits on the guest: it keeps its event loop and redraw ticker running. A console wake (TUI enqueues bytes or sets EOF) readies the blocked process. If Front 1 rejects a new block state, the fallback is a non-blocking return with a distinct "would block" result plus a `rele` in the shell loop; that fallback must be stated explicitly because the shell loop changes.
- **Wake (R1/R5):** after updating `CON_IN_HEAD` and flags, the TUI sets a new machine-level console flag, raised alongside the existing `killFlag`/`inputFlag` checks in `machine/zepa.go:611-623`. Front 1 implements the console interrupt handler and is free to name the exception cause. The existing `inputFlag` path must not be reused: it still means "load a new program".

#### `read` (id 6): framing and truncation

Reconciled with `contracts.md` §3.2 rules 4–9 and the PR #52 review.

- **Byte-oriented.** `read` copies at most `min(capacity, pending)` bytes from `CON_IN_BUF` into the caller's payload at `+4`, never more than `MAX_XFER = 512`, stores the byte count at `+0`, returns the same count in W9, and advances `CON_IN_TAIL` by exactly that count.
- **One line per call; LF included.** A `read` stops after the first LF it consumes. The terminating LF is part of the copied bytes and of the count when it is consumed. A single `read` never returns bytes from two lines.
- **No terminator added.** No NUL is appended; the caller terminates strings.
- **Empty line versus EOF.** An empty line is delivered as a single LF and returns 1, never 0. `read` returns 0 at EOF only, which means the ring is empty **and** `CON_IN_FLAGS.EOF` is set. Pending bytes are always delivered before EOF: while any byte is pending, `read` returns data even if `EOF` is set.
- **Zero capacity.** A capacity of 0 returns 0, writes 0 to `+0` and consumes nothing. It is not EOF.
- **Lines longer than `MAX_LINE = 128`.** No byte is dropped. A line longer than the caller's capacity is delivered deterministically in chunks: each `read` returns the next `min(capacity, bytes up to and including the LF)` bytes and leaves the remainder in the ring for the next call. Only the last chunk carries the LF. Chunk boundaries depend only on the ring contents and the capacities passed, never on timing, because the TUI enqueues whole lines. A caller that wants a whole line loops until it observes the LF; the shell's own truncate-and-drain rule for overlong lines is Front 3's (`contracts.md` §3.2 rule 8), not the kernel's.

#### `write` (id 7): all-or-nothing

Reconciled with `contracts.md` §3.2 rule 3 (`contracts.md:90`). This replaces the draft's short-write proposal.

- **All-or-nothing up to `MAX_XFER = 512`.** For `0 < length ≤ 512`, if the output ring has at least `length` free bytes (`1024 - (CON_OUT_HEAD - CON_OUT_TAIL)`), the kernel copies all `length` bytes to `CON_OUT_BUF`, advances `CON_OUT_HEAD` by `length` and returns `length`.
- **Insufficient space.** If the output ring has fewer than `length` free bytes, `write` returns the defined negative error, copies 0 bytes and leaves `CON_OUT_HEAD` unchanged. It may set `CON_OUT_FLAGS.OVERFLOW` as a diagnostic. A `length` above 512 is also rejected with a negative error and 0 bytes copied; it is never truncated to 512. The negative error class is `contracts.md` §3.1 ("negative on error"); its values are owned by F1-01 (#53), which has not yet landed its error table. F1-07 (#59) currently proposes `-3` for insufficient space and `EINVAL` for a length above 512. This bridge does not freeze either value.
- **Forbidden results.** Partial writes (a return between 1 and `length - 1`) and zero-byte short writes (a return of 0 for `length > 0`) are forbidden. A `length` of 0 returns 0 and copies nothing; that is not a short write.
- **No blocking.** `write` never blocks the calling process on the TUI and never waits for a drain. A caller that receives the negative error may yield (`rele`) and retry the whole buffer. Because the ring holds 1024 bytes, any legal write fits once the TUI has drained enough of the ring.
- **Drain (R2).** The TUI drains the output ring on each refresh tick and appends the bytes to a scrollable **Console** pane; it advances `CON_OUT_TAIL` only after copying. Bytes are displayed verbatim; escape sequences are not interpreted.

### 3.4 TUI-side console mode

Front 1 implements console mode in F1-08 (#60). A new debugger command `console` toggles attachment:

- `console on` sets `ATTACHED`, switches the input field's submit target to the guest, and starts a **console pump**: the TUI issues `StepChan` continuously (instead of the 100 ms `play` ticker) while redrawing at a bounded rate (for example every 100 ms). The pump stops on `console off`, on a breakpoint stop, or on `q`.
- `console off` clears `ATTACHED`, stops the pump, and restores the debugger command parser.
- While detached, every existing command behaves exactly as today.

The pump exists because `play` at 100 ms/step cannot execute the kernel/shell path in demo time. It is a TUI scheduling change, not a VM change, and it ships with F1-08's console mode. How breakpoints and single-step interact with it remains open (§4 item 4).

### 3.5 Reproducible demo sequence (target for F1-12 and F3-12)

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

Expected, for the F1-12 and F3-12 evidence runs:

- `console on` reports attachment and the pump starts; the panel stays responsive.
- `echo hello world` produces exactly `hello world\n` on the Console pane.
- `wc` consumes the two lines and returns its counts when Ctrl+D is pressed; the shell does not hang.
- `bogus` produces the shell's error message and returns to the prompt.
- `exit` terminates the shell; no fault is reported in the PCB Vector at any point.

Exit-status capture is deliberately not in this sequence. Arming `b 4036` while the console pump is running is an execution-coordination problem (the current `b` is itself a foreground step-run, so issuing it before `exit` would step a blocked shell forever, and issuing it after `exit` races cleanup). F3-12 must capture status 0 through an armed-breakpoint/run mechanism or via its harness; see §4 item 4. This sequence proves R1–R5 and the console transcript for R6, not the exit code.

The sequence depends on the `console on|off` commands and on the pump. It cannot run against `zepa-machine @ e8fd798`, which has no console, so it is not an acceptance criterion of #48. #48 is done when this document is amended and signed. The executable demo is owned by **F1-12** (#64), which produces the Front 1 evidence on a console-capable revision, and **F3-12** (#4), which owns the byte-for-byte assertions and the status-capture harness. It becomes runnable once F1-03, F1-06, F1-07 and F1-08 land.

### 3.6 Ownership split

| Side | Owns |
|---|---|
| **Front 1** (@RenanAF18) | Kernel plumbing: reservation, bitmap marking, mapping and header zeroing of `0x3012A000` (F1-03, #55); `CON_*` layout; `read` per §3.3 (F1-06, #58); all-or-nothing `write` per §3.3 (F1-07, #59); console interrupt, blocked-reader state and wake; the `machine` accessor and console flag. **TUI console integration (F1-08, #60):** `console on` / `console off`, the Console pane, input routing, Ctrl+D, the output drain loop and the console pump. Executable demo evidence (F1-12, #64). |
| **Front 3** (@matheusvir) | Shell read loop; LF and EOF consumption; retry after a negative `write`; the `stub_read` / `stub_write` swap; the demo script and its byte-for-byte assertions (F3-12, #4). |
| **Front 2** (awareness only) | #24 (F2-08 execution coordination): no console ownership and no console-block layout changes. |

## 4. What is NOT decided here

The following are deliberately left open. None of them may be invented by an implementer without a Front 1/Front 3 decision recorded on #48 or in #8.

1. **Blocking on boot / before attach.** What `read` does if a console client is not attached, and whether `read` blocks forever, returns EOF, or faults when no console session exists. The signed mechanism assumes the shell is attached before it reads.
2. **TUI focus management and key routing.** How the operator switches between the debugger field and the console field; what Esc does while attached; whether debugger commands remain available via a prefix while attached; how the page-table overlay interacts with console mode. The demo sequence assumes a mode toggle, not a focus policy.
3. **Escape sequences.** Arrow keys, Ctrl+C (today it quits the whole TUI, `tui.go:328-331`), Ctrl+Z, backspace and any other control byte. This bridge only freezes LF, CR stripping and Ctrl+D-as-EOF. In particular, guest interrupt versus debugger quit is unresolved.
4. **Execution pacing and breakpoints during console mode.** The pump ships with F1-08 (§3.4). Still open: how breakpoints and single-step interact with the pump; how a breakpoint is armed **without** running the guest synchronously (the current `b` steps in a goroutine until the PC matches, which cannot be combined with a shell blocked in `read`), and the redraw rate. Without a decision, R6 proves the console transcript but not the exit status at `b 4036`.
5. **Console ownership with multiple processes.** Which PID owns the console after `fork`, what a child inherits, and what happens if two processes read concurrently. The shell demo is single-reader; a general answer is out of scope.
6. **Output-ring back-pressure.** `write` semantics are decided in §3.3 (all-or-nothing, never blocks, no partial or zero-byte short writes). Console scrollback size and whether output produced before `console on` is buffered remain open.
7. **Interrupt cause numbering.** Front 1 owns the choice of exception cause for the console wake and must publish it in #8/zepa-machine docs. This bridge intentionally does not assign a number.
8. **Reset/teardown.** Whether `console off` flushes or discards unread guest input, and how a new `input` interacts with a stale console block.

## 5. Sign-off

| Role | Person | Scope | State |
|---|---|---|---|
| Front 1 technical definition | @RenanAF18 | Accepts/amends §3.2–3.3; owns kernel console plumbing | Signed |
| Front 3 lead / requirements | @matheusvir | Confirms §1; owns shell loop and demo assertions | Signed |
| Reviewer | @carlosarthurns | Reviews the signed bridge | Approved |

@matheusvir signs for Front 3 as global lead even while also owning Front 1 tasks; @carlosarthurns reviews for Front 1. Acceptance is recorded as comments on [#48](https://github.com/matheusvir/zesh/issues/48). `contracts.md` references this file as the signed console bridge; this file remains the bridge record and demo reference.
