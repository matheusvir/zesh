# Front 3 shell contracts

Status: **frozen v1 candidate** for the Front 3 shell, utility, and harness arc. Pending user approval and the Front-1/Front-2 review in task 4.2.

Ground truth: `zepa-machine` submodule, commit `e8fd798` (`sackOS-paginated`). Every kernel citation below is a line in `zepa-machine/sackOS/kernel.asm` at that revision unless another file is named. Breakpoint addresses and kernel line numbers are revision-pinned; see section 9.3 for the re-derive rule.

This document is normative for Front 3 code. It does not redefine Front 1 or Front 2 surfaces; those appear as change requests in section 10.

## 1. Register discipline

### 1.1 Syscall registers

| Role | Register | Rule |
|---|---|---|
| Syscall id | W9 | The `SYSCALL #n` instruction writes `n` into W9 before trapping. Do not preload W9. The kernel dispatcher reads W9. |
| Argument | W8 | At most one argument, in W8. It is read by the kernel from the saved PCB copy. |
| Return | W9 | The kernel writes the result into PCB W9 and restores it to the CPU on resume. |
| Dead state | W8, W9 | Neither register may hold live state across a syscall. Treat both as destroyed. |

Ground truth: the `SYSCALL` operation stores the instruction immediate in W9 (`machine/zepa.go`, `func (m *Machine) syscall`), the exception path saves W8 and W9 into the PCB (`kernel.asm:186-189`), and `syscall_int` dispatches on W9 (`kernel.asm:747-771`). Returning through `schedule` restores the saved registers.

The current kernel also saves and restores W0 through W7 around a syscall. Front 3 code SHALL NOT rely on that as an ABI guarantee. Only W9 carries a defined return value; W8 and W9 are never live across a call.

### 1.2 Internal call convention

Internal calls, including every `stub_*` call and every `rt.asm` helper, use the same convention:

| Role | Register |
|---|---|
| Return link | W8 |
| Argument 1 | W7 |
| Argument 2 | W6 |
| Argument 3 | W5 |
| Return value | W9 |

No register is callee-saved. A callee may clobber W0 through W7 and W9. The callee returns with `JMPR W8`. The caller must not expect W8 or W9 to survive the call.

Utilities are functions under this convention. A utility returns its status in W9 and executes `JMPR W8`. The spawn path or the harness owns the actual `exit`; a utility does not issue `SYSCALL #2` unless its task says otherwise.

## 2. Syscall invocation

A syscall is written as:

```asm
MV W8, #arg          ; omit for a syscall with no argument
SYSCALL #id
; W9 now holds the return value
```

Rules:

1. The id is the immediate operand of `SYSCALL`. `MV W9, #id` before the instruction is pointless because the instruction overwrites W9.
2. A syscall has zero or one argument. Multi-argument syscalls are not part of this contract (F1-CR-2).
3. W8 and W9 are dead after the instruction. Do not branch on W8 and do not keep a loop counter in W9.
4. A syscall may reschedule the process. W0 through W7 are preserved by the current kernel, but they are caller-saved by contract.

## 3. Frozen syscall table and buffer encoding

### 3.1 Syscall table

| Id | Name | Argument | Return | Owner | State at `e8fd798` |
|---|---|---|---|---|---|
| 0 | `fork` | none | Parent: child PID in W9. Child: `-2` in W9. No free PCB: `-1` in W9. | Kernel | Implemented (`kernel.asm:969-1379`) |
| 1 | `wait` | W8 = 4-aligned status slot address | Child PID in W9; child status word written to the slot. No child: `-1` in W9. Bad slot: fault, PCB W9 = 1. | Kernel | Implemented (`kernel.asm:1381-1602`) |
| 2 | `exit` | W8 = status word | Does not return | Kernel | Implemented (`kernel.asm:1605-1635`) |
| 3 | `getPID` | none | Running PID in W9 | Kernel | Implemented (`kernel.asm:1638-1661`) |
| 4 | `rele` | none | No defined value | Kernel | Implemented as a reschedule (`kernel.asm:1664-1665`) |
| 5 | `exec` | Front 2 defined | Front 2 defined | Front 2 | Not dispatched at `e8fd798`; Front 3 must not redefine it |
| 6 | `read` | W8 = buffer pointer, length-prefixed | W9 = byte count; 0 at EOF; negative on error | Front 1 implementation, Front 3 contract | Not dispatched at `e8fd798`; F1-CR-1 |
| 7 | `write` | W8 = buffer pointer, length-prefixed | W9 = byte count; negative on error | Front 1 implementation, Front 3 contract | Not dispatched at `e8fd798`; F1-CR-1 |
| 8 | `readfile` | **RESERVED**, one argument in W8 | Pending Front 2 | Front 2 | Not dispatched at `e8fd798`; F2-CR-1 |

Verification at `e8fd798`: `syscall_int` compares W9 against 0, 1, 2, 3, and 4 in that order (`kernel.asm:753-771`). Any other id takes the invalid-syscall path that stores `-1` in PCB W9 and reschedules (`kernel.asm:773-796`). Therefore ids 5, 6, 7, and 8 are free in the current dispatcher; ids 5 and 8 belong to Front 2, and ids 6 and 7 are frozen here for Front 1 to implement under F1-CR-1.

`exec` (5) is owned by Front 2 as `ImageID`-based execution. Front 3 code SHALL NOT issue `SYSCALL #5` directly. Only the real `stub_exec` supplied for F3-13 may do so.

### 3.2 Length-prefixed buffer encoding

A read or write buffer is a word count followed by payload bytes:

| Offset | Read | Write |
|---|---|---|
| `+0` | Capacity in bytes, supplied by the caller | Length in bytes, supplied by the caller |
| `+4` | Payload area | Payload area |

Rules:

1. The count word is a 32-bit value.
2. A single `read` or `write` call transfers at most 512 payload bytes (`MAX_XFER = 512`). Larger transfers are loops at the caller.
3. `write` is all-or-nothing for lengths up to 512 bytes. It returns the length on success and a negative value on failure; it never partially writes a short count.
4. `read` returns the number of bytes copied into `+4` and stores that count at `+0`. It returns 0 at EOF. It does not append a NUL terminator; the caller terminates strings.
5. The buffer header and payload must be 4-byte aligned.
6. `readfile` is not a read/write variant. Its one-argument form is reserved (F2-CR-1); Front 3 uses the three-argument `stub_readfile` described in section 7.

Ground truth for the 512-byte bound: the current kernel has no read/write implementation, so 512 is a Front 3 design limit chosen to fit one page and to keep a single-word count safe (design decision D4). The console bridge ring is 2048 bytes per direction (`docs/int-console-io-contract.md`, section 3.2, on PR #51 until merged).

### 3.3 Static buffer sizes

| Name | Value | Meaning |
|---|---|---|
| `MAX_LINE` | 128 bytes | Maximum input line payload, excluding terminator |
| `MAX_ARGS` | 16 | Maximum argv entries, including `argv[0]` |
| `ARGV_STR_CAP` | 128 bytes | Total inline string area in the argv window |
| `MAX_XFER` | 512 bytes | Maximum payload per read or write call |
| `MIRROR_CAP` | 3068 bytes | Output mirror payload capacity |
| `READFILE_CAP` | 1024 bytes | Recommended maximum `stub_readfile` destination |

## 4. Argv transport

### 4.1 Fixed in-image window

Every utility image carries a fixed argv window inside its own image extent:

| Address | Size | Field |
|---|---|---|
| `0x004` | 4 | `argc`, a 32-bit count, `0 <= argc <= 16` |
| `0x008` | 64 | `argv[0]` through `argv[15]`, 16 absolute pointers, 4 bytes each |
| `0x048` | 128 | Inline NUL-terminated argument strings |
| `0x0C8` | 4 | Reserved, must be zero |
| `0x0CC` | 0 | Window end, exclusive |

The last valid byte of the window is `0x0CB`. The window is exactly 50 words: one `argc` word, 16 pointer words, 32 string words, and one reserved word. It is part of the 216-byte header described in section 5.

Rules:

1. `argv[i]` is an absolute virtual address. The utility image is loaded at virtual address 0, so the pointer value is also the image offset.
2. Each string is NUL-terminated and lies in `0x048..0x0C7`. A string may not cross the end of the string area.
3. `argc` counts `argv[0]` as the command name. `argc = 0` means an empty argument list.
4. Unused pointer slots contain 0.
5. The window is data. It is never executed; the header's first word jumps over it to `_start`.
6. All window addresses are literals. The assembler resolves labels to relative instruction offsets, so a label may not be used as an absolute address in `MV`, `LDD`, or `STRD`.

### 4.2 Staging rule: before `SYSCALL #0`

The shell stages the argv window in its own image **before** it executes `SYSCALL #0` (`fork`). The fork page copy delivers the staged bytes to the child.

```asm
; 1. write argc, pointers, and strings into 0x004..0x0CB
; 2. then fork
SYSCALL #0
```

The parent must not attempt to write the child's memory after the fork. Fork copies the parent's mapped pages at the syscall (`kernel.asm:1251-1271`); the parent has no mapping to the child's pages afterward. The child reads the window from its own copy.

Ground truth for the copy: `fork` scans all 786432 page-table entries (`kernel.asm:1137-1150`), and for each valid PTE it maps a frame in the child and copies the 4 KB page (`kernel.asm:1232-1271`). The child's W9 is set to `-2` and the parent's W9 to the child PID (`kernel.asm:1298-1307`).

### 4.3 Child entry and the utility table

The child reaches the utility through the in-image utility table. The table is part of the same fat image, so the argv window is already present in the child's copy. A table entry is a code address; the child jumps to it with `JMPR`.

The spawn path sets W8 to a return trampoline before jumping to the utility. The utility returns its status in W9 and executes `JMPR W8`. The trampoline copies W9 into W8 with `OR W8, W9, W9` and issues `SYSCALL #2`. This keeps `exit` ownership in the spawn path (design decision D7).

### 4.4 Real `exec` limitation

Real `exec` (5, `ImageID`) loads a new image. It does **not** carry dynamic argv in the current design. A utility entered through real `exec` may rely only on argv that was assembled statically into its image at `0x004..0x0CB`. Dynamic argv delivery through `exec` is out of scope and is tracked as F2-CR-1. F3-13 uses a static-argv echo variant for the host-loaded demo.

## 5. Image layout and `rt.asm` prologue

### 5.1 Address map

| Range | Size | Use |
|---|---|---|
| `0x0000..0x00D7` | 216 bytes | `rt.asm` header: jump word, argv window, padding |
| `0x00D8..0x5FFF` | 24360 bytes | Utility and shell code; code end must be `<= 0x6000` exclusive |
| `0x6000..0x6BFF` | 3072 bytes | Output mirror; payload at `0x6000`, length word at `0x6BFC` |
| `0x6C00..0x7FFF` | 5120 bytes | General data |
| `0x7230` | 4 bytes | Frozen wait status slot |
| `0x8000..0xFFFF` | 32768 bytes | Outside the Front 3 data split; do not use |

The image is loaded at virtual address 0 and the first page is mapped by the loader (`kernel.asm:603-631`). Code above `0x6000` is forbidden even though the loader accepts a larger image. The 24 KB code cap is a Front 3 choice, not a loader limit.

Loader limits: `LoadBuffer` rejects an image longer than `65536 - 4 = 65532` bytes (`machine/zepa.go`, `bufferSize` and `LoadBuffer`). The cross-assembler emits 4-byte words, so every image length is a multiple of 4. An image may be shorter than `0x8000`; pages inside the loaded image length are mapped by the loader, and pages beyond it are demand-mapped on first touch by the page-fault handler (`kernel.asm:831-964`).

### 5.2 Mirror format

The fake `stub_write` writes to the output mirror:

| Address | Field |
|---|---|
| `0x6000` | First payload byte |
| `0x6BFC` | Total payload length, 32-bit, little-endian |
| `0x6C00` | End of mirror |

Payload capacity is `0x6BFC - 0x6000 = 3068` bytes. A fake write that would exceed capacity fails with a negative return and copies nothing. The mirror is secondary evidence (section 9); the primary evidence is an in-guest comparison and `exit 10`.

### 5.3 `rt.asm` prologue

Every image begins with the same 216-byte header:

| Offset | Content |
|---|---|
| `0x000` | One `JUMP _start` word. At instruction 0 the label resolves to a relative offset of 54 instructions, so the CPU lands on `0x0D8`. |
| `0x004..0x0CB` | The 200-byte argv window from section 4.1. Placeholder words; the shell overwrites them with runtime data before fork. |
| `0x0CC..0x0D7` | Three reserved padding words. Never executed. |
| `0x0D8` | `_start`, the first utility or shell instruction. |

Build-time assertions:

1. The assembled `rt.asm` object is exactly 216 bytes.
2. The symbol `_start` resolves to byte address `0x0D8`, which is instruction index 54.
3. The first instruction is a jump whose relative immediate is `54`.

The assert belongs to the image build pipeline (F3-15). A per-utility prologue is forbidden because it would move the frozen window and code addresses.

### 5.4 Assembler constraints

The cross-assembler has no data-section directive. Every line is an instruction or a label; a label is resolved to a relative instruction offset, not to an absolute address. Consequences:

1. Put data in the image with instructions (`STRD`, `STRB`) or generate it at runtime. Large fixtures are generated at runtime; small byte strings may be materialized with `STRD`/`STRB`.
2. Use literal addresses in `MV`, `LDD`, and `STRD`. Never write `MV W0, #some_label`.
3. `MV` takes a 16-bit signed immediate. Every frozen Front 3 address is at or below `0x7FFF`, so every frozen address is directly loadable. Addresses at or above `0x8000` require construction with shifts and adds.
4. `MV` does not copy a register. Copy with `OR Wd, Ws, Ws`; this is the idiom used to move a `stub_*` argument from W7 into the syscall argument register W8.

## 6. Exit codes and wait status

### 6.1 Exit-code table

`exit` takes the status from PCB W8 (`kernel.asm:1627-1633`). The kernel stores that value into PCB W9 and kills the process (`kernel.asm:1635`). The status is observable in the PCB until cleanup.

| Code | Meaning | Test use |
|---|---|---|
| 0 | Success | Clean exit |
| 1 | General fault, including a bad wait slot | Never a test result |
| 2 | External kill (`kill <pid>`) | Never a test result |
| 3 | Page fault or out of frames | Never a test result |
| 4 | Exec invalid (Front 2) | Never a test result |
| 5 through 9 | Reserved | Do not use |
| 10 | Test pass, base code | Primary pass |
| 11 through 59 | Test pass with value `10 + N`, `1 <= N <= 49` | Primary pass with a small payload |
| 60 | Test failure, base code | Primary failure |
| 61 | Test failure, alternate code | Primary failure |
| 127 | Command not found | Shell only |

Codes 1 through 4 are reserved for kernel or Front 2 outcomes and SHALL NOT be used as test results. A test that needs to report a value uses `10 + N` with `N <= 49`.

The `false` utility keeps Unix semantics and exits with 1. Because 1 is also the general-fault code, `false` SHALL NOT be validated by its standalone status. It is validated on the clean-exit path at breakpoint `b 4036`:

1. Stop at `b 4036` (`0x0FC4`), the instruction after `exit` stores the status in PCB W9 and before cleanup.
2. Read PCB W9. It must be 1.
3. Confirm the saved PC is one word past the `SYSCALL #2` instruction.
4. Confirm the fault handler was not taken. PC 4036 is reached only through the `exit` path; the fault path jumps directly to `kill`.

For a positive wait-collection proof, use a child that exits with 7. The parent waits, adds 10, and exits with 17. Status 17 cannot be confused with a fault, a kill, or a pass base code.

### 6.2 Wait touch idiom

`wait` requires a status slot that is 4-byte aligned, in user space, and mapped (`kernel.asm:1405-1434`). An unmapped, misaligned, or kernel-space slot faults the parent with PCB W9 = 1 (`kernel.asm:800-827`). The kernel then writes the child status to the slot and returns the child PID in W9 (`kernel.asm:1511-1519`).

Every wait SHALL use this sequence:

```asm
STORE W0, W1        ; W1 = 0x7230, exact frozen slot; this touch maps the page
OR W8, W1, W1       ; W8 = status slot address; MV cannot copy a register
SYSCALL #1          ; W9 = child PID; memory[0x7230] = child status
```

Rules:

1. The slot is `0x7230`, 4-byte aligned, and lies in the data region.
2. The `STORE` must target the exact slot and must appear immediately before the W8 load and `SYSCALL #1`. It is the page-touch that makes the slot mapped.
3. The value stored by the touch is irrelevant; it is overwritten by the kernel when the child is collected.
4. Wait returns the child PID in W9 on success. A return of `-1` means the process has no children (`kernel.asm:1437-1451`).
5. Never reuse the slot for anything else while a wait is outstanding.
6. Do not busy-wait on the slot. `wait` blocks and reschedules.
7. If this sequence is inside a function, save the W8 return link before the W8 load and restore it before `JMPR W8`. `SYSCALL` restores the argument that was in W8, not the link.

## 7. Stub layer

### 7.1 Public labels and signatures

All four public labels use the internal call convention from section 1.2.

| Label | Arguments | Return | Fake behavior (`stubs.asm`) | Real behavior (`syscalls.asm`) |
|---|---|---|---|---|
| `stub_read` | W7 = buffer pointer (`[0]` = capacity) | W9 = count, 0 at EOF, negative on error | Copy the next line from a code-embedded or runtime-generated canned script into `+4`; store count at `+0`; no NUL terminator | Save the W8 link, `OR W8, W7, W7`, `SYSCALL #6`, restore the link, `JMPR W8` |
| `stub_write` | W7 = buffer pointer (`[0]` = length) | W9 = length, negative on error | Append payload to the mirror at `0x6000`; update `0x6BFC`; all-or-nothing at capacity | Save the W8 link, `OR W8, W7, W7`, `SYSCALL #7`, restore the link, `JMPR W8` |
| `stub_exec` | W7 = utility table index; W6 = argv window address (`0x004`); W5 = argc | Parent: W9 = child PID, or `-1` on fork failure. Child: never returns to the caller. | `SYSCALL #0`; parent returns the child PID; child loads the table entry, sets its own W8 to the exit trampoline, and jumps | `OR W8, W7, W7` (ImageID); `SYSCALL #5` (Front 2 `exec`); never returns; no dynamic argv |
| `stub_readfile` | W7 = path pointer; W6 = destination; W5 = maximum bytes | W9 = bytes copied (truncated to W5), or negative if not found | Resolve the name against an embedded name-to-blob table; copy whole file; truncate to W5 | Front 2 filesystem read (F2-CR-1); id 8 remains one-argument and RESERVED until then |

All real stubs save the W8 return link in a scratch register before they overwrite W8 with the syscall argument, and restore it before `JMPR W8`. This is required because `SYSCALL` saves and restores the W8 value at the trap, which is the syscall argument, not the stub's return link. Fake stubs leave W8 untouched and return with `JMPR W8`.

### 7.2 Swap rule

`stubs.asm` is the fake implementation. `syscalls.asm` is the real implementation. Both define the same four labels with the same signatures and the same W9 return shape. The swap changes the file, never the call sites.

- F3-12 swaps `stub_read` and `stub_write` to their real forms after F1-CR-1 lands.
- F3-13 swaps `stub_exec` and `stub_readfile` after F2-CR-1 lands.
- Utilities and the shell call only the four labels. They never call syscall ids 5, 6, 7, or 8 directly.

### 7.3 `stub_exec` divergence

The fake `stub_exec` returns in the parent and never returns to the caller in the child. The child path jumps to a utility and the utility returns to a trampoline that exits with the utility's W9. The real `exec` diverges: it replaces the calling image and never returns in either process. Call sites must therefore treat the child path as "does not return" and must not place post-exec cleanup in the child.

## 8. Console dependency

Front 3 does not define the TUI console mechanism. The requirements are frozen in the INT-06 bridge:

- `docs/int-console-io-contract.md`, requirements R1 through R6. The file is on branch `docs/int-06-console-io-1` and PR #51 until merged.
- R1: a TUI mechanism delivers a typed line to `read` (6).
- R2: `write` (7) output is displayed on a readable console surface.
- R3: newline semantics are explicit; one line terminator byte.
- R4: an EOF syntax makes a blocked `read` return 0.
- R5: blocking does not freeze the TUI.
- R6: a reproducible command sequence for F3-12.

At `e8fd798`, ids 6 and 7 are not implemented; the kernel dispatcher handles only 0 through 4 (`kernel.asm:753-771`) and returns `-1` for any other id (`kernel.asm:773-796`). Until F1-CR-1 lands, the stub layer is the only implementation. F3-12 is the only Front 3 task blocked by F1-CR-1; the rest of the arc runs on stubs.

The INT-06 draft proposes a console frame at physical `0x00303000`. That address collides with the page table of PCB 1:

- PCB vector base: `0x2024` (`kernel.asm:4`, `kernel.asm:998`).
- PCB size: `0x300050` (`kernel.asm:988-993`).
- PCB 1 base: `0x302074`.
- PCB 1 page table: base plus 80 bytes, `0x3020C4` through `0x6020C4` (3 MB).
- The console frame `0x303000` falls inside that page table.

F1-CR-4 requests a free frame at or above `0x30127024`. The kernel page table occupies `0x30007024..0x30107024`; the frame bitmap occupies `0x30107024..0x3010F024`. The first page-aligned candidate above the recommended base is `0x30128000`. This document does not bless the console frame address.

## 9. Test evidence conventions

### 9.1 Primary and secondary evidence

Primary evidence is in-guest:

1. Compare the observed bytes against an expected byte string in guest memory.
2. Exit with 10 on success, 60 or 61 on failure.
3. Keep codes 1 through 4 out of test results.

Secondary evidence is the output mirror at `0x6000` plus its length at `0x6BFC`. It is useful for humans but is not the assertion. At `e8fd798` the TUI Memory pane is PC-centered and does not provide an arbitrary raw byte dump; a `mem <addr> <len>` command is requested as F1-CR-3. When that command lands, the mirror becomes easier to inspect, but it remains secondary.

### 9.2 Breakpoints

The following PC breakpoints are frozen for `e8fd798`:

| Command | Decimal | Meaning |
|---|---|---|
| `b 0` | 0 | Loaded program entry, before its first instruction |
| `b 4036` | 4036 (`0x0FC4`) | Immediately after `exit` stores the status in PCB W9, before cleanup (`kernel.asm:1633`) |
| `b 5536` | 5536 (`0x15A0`) | Kernel idle loop after process cleanup |

Observed offsets from the F3-00 recon: `b 300` stops at kernel boot complete; `b 4036` is `0xC0000FC4`; `b 5536` is `0xC00015A0`.

Rules:

1. Capture PCB W9 at `b 4036`, before the process is removed. Do not wait for `b 5536` to read a status.
2. Reading the live CPU W9 is not the same as reading the saved PCB W9. Use the PCB Vector pane or the saved-register view.
3. `b` has no timeout. A breakpoint that is never hit spins forever. Quit the TUI to recover.
4. Breakpoints use decimal addresses in the TUI. The hex values above are documentation only.

### 9.3 Revision pinning and re-derive rule

The breakpoint addresses and kernel line numbers apply only to `e8fd798`. After any kernel change:

1. Re-run the three F3-00 samples (`small`, `syscall`, `fork`) on the new revision.
2. Re-derive the entry, post-exit, and idle PCs.
3. Update this document in the same PR as the kernel bump.
4. Re-run one end-to-end probe before any shell evidence is recorded.

An unreviewed breakpoint address is not evidence.

### 9.4 Fork tests use breakpoints, not `play`

`fork` scans 786432 page-table entries (`kernel.asm:1137-1150`) and copies every mapped page (`kernel.asm:1251-1271`). A one-page parent takes roughly 11 million instructions. At `play`'s 100 ms per instruction, that is about 13 days per fork. Fork tests SHALL use breakpoints only. `play` is acceptable only for non-fork demos that are short enough to finish.

### 9.5 Evidence transcript format

A recorded run names, in order:

1. The revision (`git -C zepa-machine rev-parse HEAD`).
2. The exact TUI commands (`b`, `input`, `d`, `reg`, `pcb`, `refresh`).
3. Each observed breakpoint line with its instruction count.
4. The PCB W9 value before cleanup, with the PID.
5. The in-guest result (exit code 10 or 60/61) and the mirror length.
6. Any skipped check, with the reason.

Do not paste reconstructed output. If a run was not executed, label the artifact as unexecuted.

## 10. Boundaries and change requests

### 10.1 What this contract does not define

- The TUI console mechanism, console surfaces, newline and EOF rules, or blocking states. Owned by Front 1 through INT-06.
- Multi-argument syscalls. Optional Front 1 extension.
- The raw-memory dump command. Requested from Front 1.
- Filesystem path resolution, file identity, or persistent storage. Owned by Front 2.
- `exec` internals, `ImageID` layout, or exec failure semantics. Owned by Front 2.
- The console frame address. Proposed by INT-06; corrected by F1-CR-4.

### 10.2 Change-request table

| ID | Owner | Request | Blocks | Status |
|---|---|---|---|---|
| F1-CR-1 | Front 1 | Console input/output channel satisfying R1 through R6, plus kernel `read` (6) and `write` (7) | F3-12 only | Open, non-blocking for F3-03 through F3-11 |
| F1-CR-2 | Front 1 | Optional multi-argument syscalls using W7 and W6 as argument 2 and 3 | Nothing | Optional, non-blocking |
| F1-CR-3 | Front 1 | `mem <addr> <len>` raw memory dump in the TUI | Mirror-primary acceptance criteria only | Open, non-blocking; in-guest asserts are normative |
| F1-CR-4 | Front 1 | Move the proposed console frame off PCB 1's page table; use a free frame at or above `0x30127024` | INT-06 | Open, non-blocking for F3-01 |
| F2-CR-1 | Front 2 | Real `exec` argv transport and `readfile` (8) read-only in-memory filesystem semantics | F3-13 only | Open, non-blocking for the stub arc |

### 10.3 Review and revision

This is version 1 of the `shell-contracts` capability. Any change to a frozen value requires:

1. A written reason in the change request or issue.
2. A re-read of the affected kernel path at the pinned revision.
3. A review from the owning front when the change crosses a front boundary.
4. An update to this document in the same PR as the code or issue change.

Silent address drift is a contract violation.
