# F3-02: assembler capability spike

Issue: [#9](https://github.com/matheusvir/zesh/issues/9). Objective: answer the
assembler questions that block the runtime idiom library, using probes loaded
through the TUI `input` path, and record a go/no-go for building `rt.asm` in
F3-03 (#15) and F3-04 (#16).

Status: ready for review — pending reviewer re-run, PR, and #9 validation. All
four questions are answered with TUI probes on `e8fd798`; go/no-go for F3-03
(#15) and F3-04 (#16) is recorded in section 5. This is a spike: no `rt.asm`,
`memcpy`, `strcmp`, `strlen`, `itoa` or `do_wait` code is written here.

## 1. Ground truth and environment

| Item | Value |
|---|---|
| `zesh` revision | `7ff24f8e51bf47aa5a6d3026857cd40589183a57` (`main`, includes the frozen F3-01 contracts) |
| `zepa-machine` pin | `e8fd79859c5766c33664bf408f8a86982abdf126` (`sackOS-paginated`) |
| Local submodule checkout | `93f1d28874550861f3d174aa04efe2b42c2fdd3a` — divergent, not used as evidence |
| Toolchain | `go1.26.10` linux/amd64 (`go.mod` requires Go >= 1.23) |
| Terminal driver | `tmux 3.8`, detached session `zepa-spike`, 220x55 |

The local submodule checkout is left untouched. Evidence runs use a detached
worktree of the pinned commit. Set repository-relative path variables first:

```bash
export ZESH_ROOT=$(git rev-parse --show-toplevel)
export MACHINE_WT=${MACHINE_WT:-/tmp/opencode/zepa-machine-e8fd798}
export KERNEL_BIN=${KERNEL_BIN:-$MACHINE_WT/zepa-kernel-e8fd798}
```

```bash
cd "$ZESH_ROOT/zepa-machine"
git worktree add --detach "$MACHINE_WT" e8fd79859c5766c33664bf408f8a86982abdf126
```

Build the kernel TUI from that worktree (the kernel path is relative to the
working directory):

```bash
cd "$MACHINE_WT"
go build -tags kernel -o "$KERNEL_BIN" .
"$KERNEL_BIN" 2GB 128
```

### Driving the TUI without an interactive terminal

The session used for this spike has no TTY, and `tview`/`tcell` require one. The
TUI is therefore started inside a detached `tmux` session and driven with
`send-keys`, while observations are taken with `capture-pane`:

```bash
tmux new-session -d -s zepa-spike -x 220 -y 55 \
  "cd '$MACHINE_WT' && '$KERNEL_BIN' 2GB 128"
tmux send-keys -t zepa-spike 'b 300' Enter      # boot-complete breakpoint
tmux send-keys -t zepa-spike 'input asm/samples/small.asm' Enter
tmux send-keys -t zepa-spike 'b 0' Enter        # loaded program entry
tmux capture-pane -t zepa-spike -p
```

The repository ships a driver for these steps:
`evidence/f3-02/run_probe.sh start|run|cmd|wait|cap|stop`. `run_probe.sh run
<probe>` copies the probe into `$MACHINE_WT/evidence-probes/` and sends a
relative `input` path, so no user-specific absolute path is required:

```bash
"$ZESH_ROOT/evidence/f3-02/run_probe.sh" start
"$ZESH_ROOT/evidence/f3-02/run_probe.sh" run jmpr_range_discriminating.asm
"$ZESH_ROOT/evidence/f3-02/run_probe.sh" wait 'input sent' 20
```

When driving `tmux` manually, the calling shell expands the variable before the
command reaches the TUI:

```text
input $ZESH_ROOT/evidence/f3-02/<probe>.asm
```

## 2. Verified baseline

The driver reproduces the F3-00 reconnaissance results exactly on `e8fd798`,
which is the precondition for trusting later observations:

| Command | Observed |
|---|---|
| `b 300` | `Breakpoint reached at pc=300 after 1613892 instructions`, `Cycles used: 2170970`, CPU PC `0xC000012C` |
| `input asm/samples/small.asm` | `input sent (12 bytes)` |
| `b 0` | `Breakpoint reached at pc=0 after 110210 instructions`, `Cycles used: 148859` |
| `input $MACHINE_WT/asm/samples/syscall.asm` | `input sent (4 bytes)` — paths outside the checkout also work |

Boot is deterministic for this revision: the instruction and cycle counts match
`docs/f3-00-recon.md`.

## 3. Environment limitations

1. **TUI crash on concurrent register access.** A session died with
   `fatal error: concurrent map read and map write` at
   `machine/debug.go:374` (`debugRegistersTo`), reached from the 500 ms refresh
   goroutine (`tui.go:96`, `tui.go:352`). Cause: `Boot()` calls `fetch()` and
   `decode()` outside `m.mu.Lock()` (`machine/zepa.go:575-624`), and `fetch()`
   writes `m.registers[pc]`/`m.registers[ir]` unlocked; `GetRegisters()`
   (`machine/zepa.go:676`) also returns the live map, which `b` reads unlocked
   (`tui.go:214`). The crash is intermittent, not deterministic. Mitigation:
   restart the session and repeat the command sequence; record the crash as an
   environment note, never as a probe result. Do not patch the pinned revision:
   a patched TUI would no longer be evidence for `e8fd798`.
2. **`play` is unusable for long paths.** It steps every 100 ms, so the 1.6M
   instruction boot would take roughly 45 h. All runs use `b`/`d` instead.
3. **Breakpoints have no timeout.** `b <pc>` spins forever when the address is
   never reached (`tui.go:194-225`); only quitting the TUI ends it. Every
   breakpoint used by a probe must be an address that probe actually reaches.
4. **Exit status must be read before cleanup.** `b 4036` stops after `exit`
   stores the status in the process PCB's W9 and before the process is removed;
   `b 5536` is the idle loop after cleanup. Status is not observable afterwards.
5. **`input sent` means submission, not completion.** Execution starts only when
   the kernel is stepped past the input interrupt, so each probe follows `input`
   with a breakpoint at the entry PC.
6. **The memory pane is PC-centred.** Arbitrary buffer bytes are not directly
   inspectable; probes that need a memory observation must write it into a
   register or into the exit status first.

## 4. Questions and probes

Probe sources and transcripts live in `evidence/f3-02/`. Each question records
the probe, the TUI commands, the observed output and the conclusion.

### 4.1 Labels as `MV` immediates

Answered by probe execution on `e8fd798` (transcripts in `evidence/f3-02/`).

| Probe | TUI observation | Conclusion |
|---|---|---|
| `label_immediate_forward.asm` (`MV W0, alvo`, label 2 instructions ahead) | `input sent (16 bytes)`; disassembly shows `MV w0, #2`; after `d 1`: W0 = 2 (`0x00000002`), PC = 4; PCB at `b 4036`: saved W0 = 2, W1 = 7, PC = 16, W9 = 0 | Bare label assembles; value is the **instruction-count displacement** (2), not the byte offset (8) |
| `label_immediate_backward.asm` (`MV W0, base`, label 1 instruction behind) | `input sent (12 bytes)`; disassembly shows `MV w0, #65535`; after `d 2`: W0 = -1 (`0xFFFFFFFF`), W1 = 7, PC = 8 | Backward labels work symmetrically; displacement −1 is stored as `uint16` 65535 and sign-extended at execution |
| `label_immediate_hash_reject.asm` (`MV W0, #alvo`) | `Error converting instruction '[MV W0 #alvo]': ... Invalid immediate value: alvo`; no `input sent`, PCB stays empty | `#label` never matches the label table and fails immediate parsing; no process is created |

Rule for F3-03/F3-04: a bare label in `MV` yields a displacement in
**instruction units**, not bytes, and it is only directly usable by direct
branches that take instruction units (e.g. `JUMP label`). `JMPR` takes a **byte
address**, so a label materialised by `MV` must not be passed to `JMPR`
directly: shift it left by 2 (`SHL`), then add the base byte address. The
displacement is encoded in 16 bits and sign-extended at execution: a forward
label more than 65535 instructions ahead, or a backward label more than 32768
instructions behind, fails to assemble. This is a non-issue for the 64 KiB
Front 3 images.

Absolute addresses must still be built in registers.

### 4.2 Negative literals and sign extension

Answered by probe execution on `e8fd798` (transcripts in `evidence/f3-02/`).

| Probe | TUI observation | Conclusion |
|---|---|---|
| `immediate_sign_values.asm` (`#-1`, `#-32768`, `#32767`, `#32768`, `#65535`) | `input sent (24 bytes)`; disassembly shows raw unsigned halfwords (`#-1`→`#65535`, `#-32768`→`#32768`); after `d 5`: W0 = −1 (`0xFFFFFFFF`), W1 = −32768 (`0xFFFF8000`), W2 = 32767 (`0x00007FFF`), W3 = −32768 (`0xFFFF8000`), W4 = −1 (`0xFFFFFFFF`) | Parser accepts the full −32768..65535 range; execution sign-extends, so only 0..32767 load as positive — `#32768` runs as −32768, `#65535` as −1 |
| `immediate_sign_reject_low.asm` (`#-32769`) | `... immediate out of 16-bit bounds: -32769`; no `input sent`, machine stays idle | Lower bound is exactly −32768 |
| `immediate_sign_reject_high.asm` (`#65536`) | `... immediate out of 16-bit bounds: 65536`; no `input sent`, machine stays idle | Upper bound is exactly 65535 |

Rule for F3-03/F3-04: a single `MV` can only materialise 0..32767 as positive.
Anything else (large positives, absolute addresses) must be built with several
instructions (shifts/adds) in registers.

### 4.3 `_start` versus entry at VA 0

Answered by probe execution on `e8fd798` (transcripts in `evidence/f3-02/`).

| Probe | TUI observation | Conclusion |
|---|---|---|
| `entry_point_no_start.asm` (`MV W1, #5` + `SYSCALL #2`, no `_start`) | `input sent (8 bytes)`; `b 0` stops at pc=0; after `d 1`: W1 = 5, PC = 4; PCB at `b 4036`: saved W1 = 5, PC = 8, W9 = 0 | No `_start` needed; execution begins at the first instruction (VA 0); exit status 0 |
| `entry_point_start_elsewhere.asm` (`JUMP _start` + skipped `MV W1, #99` + `_start: MV W1, #5`) | `input sent (16 bytes)`; disassembly `JUMP +2`; after first `d 1`: PC = 8, W1 = 0; after second: W1 = 5, PC = 12; PCB at `b 4036`: W1 = 5, W9 = 0 | `_start` is an ordinary label; entry is still VA 0 and only the explicit `JUMP` reaches it; the skipped `MV #99` never runs |

Rule for F3-03/F3-15: image layout starts code at offset 0; `_start` is an
optional convention, required only when the program itself jumps to it (e.g. to
skip a header).

### 4.4 `JMPR` above 32 KiB

Answered by probe execution on `e8fd798` (transcripts in `evidence/f3-02/`).
The original probe `jmpr_range_32k.asm` is kept for history but is **not
discriminating**: JMPR and sequential fall-through both reach the marker at
byte `0x8000`. The review probe is `jmpr_range_discriminating.asm`,
generated deterministically by `gen_jmpr_range_discriminating.py`:

| Instr | Byte | Instruction | Purpose |
|---|---|---|---|
| 0 | 0 | `MV W0, #1` | build the address |
| 1 | 4 | `MV W1, #15` | shift count |
| 2 | 8 | `SHL W0, W0, W1` | W0 = `0x8000` = 32768 |
| 3 | 12 | `JMPR W0` | target of the question |
| 4 | 16 | `MV W8, #60` | fall-through failure status |
| 5 | 20 | `SYSCALL #2` | exit 60, marker never reached |
| 6..8191 | 24..32767 | 8186x `MV W2, #0` | padding |
| 8192 | **32768 = 0x8000** | `MV W5, #777` | arrival marker |
| 8193 | 32772 | `MV W8, #10` | success status |
| 8194 | 32776 | `SYSCALL #2` | exit 10 |

Byte math: the marker is instruction 8192, so `8192 * 4 = 32768 = 0x8000`.
Six setup/failure instructions plus 8186 padding instructions fill instructions
6..8191; total 8195 instructions = **32780 bytes = 9 pages**. A same-size
control, `jmpr_range_discriminating_control.asm` (8194 instructions, 32776
bytes, 9 pages), has no jump: 8191 padding instructions, marker at instruction
8191 (byte 32764), then `MV W8, #10` + `SYSCALL #2` (exit 10).

| Probe | TUI observation | Conclusion |
|---|---|---|
| `jmpr_range_discriminating.asm` | `input sent (32780 bytes)`; `b 32768` -> `Breakpoint reached at pc=32768 after 963182 instructions` (`Cycles used: 1321660`), W0 = 32768, W1 = 15, W5 = 0, PC = 32768; after `d 1`: W5 = 777, PC = 32772; PCB at `b 4036` (`+111` instructions): Pages = 9, W0 = 32768, W1 = 15, W5 = 777, W8 = 10, W9 = 10, PC = 32780; `b 5536` idle | `JMPR` takes the full 32-bit register with no 16-bit limit and lands on byte `0x8000`; the success path ran (W5 = 777, status 10) |
| `jmpr_range_discriminating_control.asm` | `input sent (32776 bytes)`; `b 0` -> `Breakpoint reached at pc=0 after 963176 instructions` (`Cycles used: 1321650`, no probe instruction executed); `b 32764` -> `10303` instructions (8191 padding + 64 timer slices, `clock_interrupt_count = 64`); after `d 1`: W5 = 777, PC = 32768; PCB at `b 4036`: Pages = 9, W5 = 777, W8 = 10, W9 = 10, PC = 32776; `b 5536` idle | The 9-page input/load path costs ~963k instructions before the first probe instruction; walking the sequential padding costs only 10303 more |

Discriminating power: a JMPR that did not jump would execute instructions 4-5,
exit 60 with W5 = 0, and never reach byte `0x8000`; the observed run instead has
W5 = 777, W8 = W9 = 10 and PC = 32780, so the marker at `0x8000` executed.
W0 = `0x8000` also proves the address was built in-register, since no single
`MV` holds it positive.

Instruction-count note: the original probe reported 963180 instructions, far
above the ~110.2k of tiny images. The same-size control isolates this: reaching
pc=0 on a 9-page image already costs 963176 instructions, and the jumping probe
needs only 6 more to reach pc=32768. The ~963k is therefore input/load cost, not
padding execution and not jump cost. The specific kernel path behind that load
cost is **not isolated** in this spike (hypothesis: page mapping / zero-fill
work); flagged for Front 2 and it does not affect the JMPR conclusion.

Evidence: `jmpr_range_discriminating.transcript.txt` and
`jmpr_range_discriminating_control.transcript.txt` (curated summaries), the
matching `.raw.txt` files (literal `tmux capture-pane -p` output), and
`jmpr_range_discriminating.sizes.txt` (`wc -c`, `sha256sum`, assembler byte
counts and marker bytes).

## 5. Decision

**GO for F3-03 (#15) and F3-04 (#16), conditional on three coding rules** (all
evidenced above by TUI probes on `e8fd798`):

1. Bare labels in `MV` yield instruction-count displacements, never absolute
   addresses (§4.1).
2. A single `MV` only materialises 0..32767 as positive; larger positives and
   absolute addresses are built multi-instruction in registers (§4.2, §4.4).
3. Code starts at offset 0; `_start` is an optional convention (§4.3).

Residual risks (accepted): the TUI race at `machine/debug.go:374` kills sessions
intermittently — rerun from `b 300`, never treat a crash as a probe result;
`play` stays unusable for long paths; a 9-page image costs ~963k instructions
in the input/load path before its first instruction (measured by the control in
§4.4; the underlying loader path is not isolated — Front 2 item, not a runtime
blocker).
