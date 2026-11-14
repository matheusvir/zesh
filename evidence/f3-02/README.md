# F3-02 evidence

Probe sources and TUI transcripts for the assembler capability spike
([#9](https://github.com/matheusvir/zesh/issues/9)). Ground truth and method:
`docs/f3-02-assembler-spike.md`.

## Path variables

Commands below are repository-relative. Set these once from the repo root:

```bash
export ZESH_ROOT=$(git rev-parse --show-toplevel)
export MACHINE_WT=${MACHINE_WT:-/tmp/opencode/zepa-machine-e8fd798}  # pinned e8fd798 worktree
export KERNEL_BIN=${KERNEL_BIN:-$MACHINE_WT/zepa-kernel-e8fd798}
```

## Running a probe

Build the pinned kernel TUI and start the tmux driver:

```bash
"$ZESH_ROOT/evidence/f3-02/run_probe.sh" build
"$ZESH_ROOT/evidence/f3-02/run_probe.sh" start
```

`run_probe.sh run <probe>` copies the probe to `$MACHINE_WT/evidence-probes/` and
sends `input evidence-probes/<probe>`, so no absolute path crosses the TUI:

```bash
"$ZESH_ROOT/evidence/f3-02/run_probe.sh" run jmpr_range_discriminating.asm
"$ZESH_ROOT/evidence/f3-02/run_probe.sh" cmd 'b 32768'
"$ZESH_ROOT/evidence/f3-02/run_probe.sh" wait 'Breakpoint reached at pc=32768' 240
"$ZESH_ROOT/evidence/f3-02/run_probe.sh" cap
"$ZESH_ROOT/evidence/f3-02/run_probe.sh" stop
```

When driving tmux manually, the calling shell expands the path before the
command reaches the TUI, so this also works:

```text
input $ZESH_ROOT/evidence/f3-02/<probe>.asm
```

At the TUI prompt:

```text
b 300
input $ZESH_ROOT/evidence/f3-02/<probe>.asm
b <entry pc of the probe>
reg
```

Probes are plain `.asm` sources with no runtime dependency, so they can be
loaded one after another in a single session. Layout rule for probes that must
not rely on `_start`: start with an observable instruction at image offset 0.

## Evidence file conventions

- `<probe>.transcript.txt` — curated summary: layout, commands, observed pane
  values and conclusion. Shell variables are shown unexpanded so the steps stay
  reproducible without a user-specific path.
- `<probe>.raw.txt` — literal `tmux capture-pane -p` output. Only `=====` command
  delimiter lines are added; the captured screens are unmodified.
- `jmpr_range_discriminating.sizes.txt` — `wc -c`, `sha256sum`, assembler byte
  counts and marker bytes for the 32 KiB JMPR probes.
- `run_probe.sh` — resolves `ZESH_ROOT`/`MACHINE_WT` and drives the TUI.
- `gen_*.py` — deterministic generators for the large probes; run from this
  directory (`python3 gen_jmpr_range_discriminating.py`).

## Naming

| Pattern | Question |
|---|---|
| `label_immediate_*.asm` | 4.1 labels as `MV` immediates |
| `immediate_sign_*.asm` | 4.2 negative literals and sign extension |
| `entry_point_*.asm` | 4.3 `_start` versus entry at VA 0 |
| `jmpr_range_*.asm` | 4.4 `JMPR` above 32 KiB |

`jmpr_range_32k.asm` is the historical, non-discriminating probe (fall-through
reaches the same marker). `jmpr_range_discriminating.asm` and
`jmpr_range_discriminating_control.asm` are the review probes: the first exits 60
immediately if the jump does not happen, the second is the same-size 9-page
image without a jump used to isolate input/load cost.
