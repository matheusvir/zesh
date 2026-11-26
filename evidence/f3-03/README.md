# F3-03 evidence

TUI runs of the runtime batch-1 tests and the image header for
[#15](https://github.com/matheusvir/zesh/issues/15). Sources live in `rt/`;
transcript format follows `contracts.md` section 9.5.

## Results

zepa-machine @ `e8fd798`, legacy TUI, each run in a fresh session.

| Run | Image | Stop at `b 4036` | PID | PCB W9 | Saved PC |
|---|---|---|---|---|---|
| `strlen_test` | 392 bytes | 215303 instructions | 0 | 10 | 192 |
| `strcmp_test` | 576 bytes | 215543 instructions | 0 | 10 | 376 |
| `memcpy_test` | 524 bytes | 215439 instructions | 0 | 10 | 324 |
| `do_wait_test` (child) | 332 bytes | 11232781 instructions | 1 | 7 | 124 |
| `do_wait_test` (parent) | | 220811 instructions | 0 | 17 | 116 |
| `rt_header_test` | 380 bytes | 111003 instructions | 0 | 10 | 372 |
| `rt_header_alone` | 216 bytes | not stepped | | | |

Boot completes at `b 300` after 1613892 instructions in every run.

## Reproducing a run

The assembler has no include, so each test is composed into `build/` first.
From the `zesh` root:

```bash
tools/rt_link.sh rt/strlen_test.asm      # also strcmp, memcpy, do_wait
cat rt/rt_header.asm rt/rt_header_test.asm > build/rt_header_test.asm
cd zepa-machine
go run -tags kernel . 2GB 128
```

At the TUI prompt:

```text
b 300
input ../build/strlen_test.asm
b 4036
```

Read W9 and PC for the PID in the process table. `do_wait_test` needs a
second `b 4036`: the first stop is the child, the second is the parent. The
`fork` takes about 11 million instructions; use breakpoints only, never
`play` (`contracts.md` section 9.4). `rt_header_alone` is `input
../rt/rt_header.asm` after `b 300`, checking only the reported size.

The issue text says `input rt/memcpy_test.asm`; that path does not exist
from the `zepa-machine/` root and the test is not self-contained, so the
linked `../build/` path is used instead.

## Files

`<run>.transcript.txt` records one run: source, commands, observed TUI lines,
skipped checks and conclusion.

`strcmp_test` was recorded in a second session: the first crashed during
boot with the known TUI race `concurrent map read and map write`
(`machine/debug.go:374`).
