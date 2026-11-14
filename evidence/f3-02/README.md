# F3-02 evidence

Probe sources and TUI transcripts for the assembler capability spike
([#9](https://github.com/matheusvir/zesh/issues/9)). Ground truth and method:
`docs/f3-02-assembler-spike.md`.

## Running a probe

From the pinned worktree of `zepa-machine` at `e8fd798`:

```bash
cd /tmp/opencode/zepa-machine-e8fd798
./zepa-kernel-e8fd798 2GB 128
```

At the TUI prompt:

```text
b 300
input /home/anderson/code/zepa/zesh/evidence/f3-02/<probe>.asm
b <entry pc of the probe>
reg
```

Probes are plain `.asm` sources with no runtime dependency, so they can be
loaded one after another in a single session. Layout rule for probes that must
not rely on `_start`: start with an observable instruction at image offset 0.

## Naming

| Pattern | Question |
|---|---|
| `label_immediate_*.asm` | 4.1 labels as `MV` immediates |
| `immediate_sign_*.asm` | 4.2 negative literals and sign extension |
| `entry_point_*.asm` | 4.3 `_start` versus entry at VA 0 |
| `jmpr_range_*.asm` | 4.4 `JMPR` above 32 KiB |

Transcripts are stored next to the probe as `<probe>.transcript.txt` and contain
the exact commands entered plus the captured pane lines that carry the
observation.
