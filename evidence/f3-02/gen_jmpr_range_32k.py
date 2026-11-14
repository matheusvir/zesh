#!/usr/bin/env python3
"""Generate jmpr_range_32k.asm: JMPR to byte 0x8000 (instruction 8192).

Layout:
  instr 0: MV W0, #1
  instr 1: MV W1, #15
  instr 2: SHL W0, W0, W1   (W0 = 0x8000, first address no single MV can hold positive)
  instr 3: JMPR W0
  instr 4..8191: 8188x MV W2, #0 (harmless padding, bytes 16..32768)
  instr 8192 (byte 0x8000): MV W5, #777 (arrival marker)
  instr 8193: SYSCALL #2
Total: 8194 instructions = 32776 bytes.
"""
from pathlib import Path

lines = [
    "; F3-02 Q-D1: JMPR to byte 0x8000 (instr 8192).",
    "; Setup builds 0x8000 in W0 (MV+SHL), JMPR W0 must land on the marker.",
    "; Discriminator: breakpoint instruction count (~110.3k jumped vs ~118.5k fell through).",
    "MV W0, #1",
    "MV W1, #15",
    "SHL W0, W0, W1",
    "JMPR W0",
]
lines += ["MV W2, #0"] * 8188
lines += [
    "MV W5, #777",
    "SYSCALL #2",
]
assert len([ln for ln in lines if ln and not ln.startswith(";")]) == 8194
Path("jmpr_range_32k.asm").write_text("\n".join(lines) + "\n")
print(f"wrote {len(lines)} lines")
