#!/usr/bin/env python3
"""Generate the discriminating JMPR-range probe and its same-size control.

Probe: jmpr_range_discriminating.asm
  instr 0: MV W0, #1
  instr 1: MV W1, #15
  instr 2: SHL W0, W0, W1      (W0 = 0x8000 = 32768)
  instr 3: JMPR W0
  instr 4: MV W8, #60          (fall-through failure path)
  instr 5: SYSCALL #2          (exit 60 if the jump does not happen)
  instr 6..8191: 8186x MV W2, #0  (padding to byte 0x8000)
  instr 8192 (byte 0x8000): MV W5, #777   (arrival marker)
  instr 8193: MV W8, #10       (success exit status)
  instr 8194: SYSCALL #2
Total: 8195 instructions = 32780 bytes (9 pages).

Control: jmpr_range_discriminating_control.asm
  instr 0..8190: 8191x MV W2, #0  (sequential padding, no jump)
  instr 8191 (byte 32764): MV W5, #777
  instr 8192: MV W8, #10
  instr 8193: SYSCALL #2
Total: 8194 instructions = 32776 bytes (9 pages).

Both files are generated deterministically next to this script.
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent


def emit_probe() -> None:
    lines = [
        "; F3-02 Q-D1 discriminating probe: JMPR must land on byte 0x8000.",
        "; Fall-through executes MV W8,#60 + SYSCALL #2 and exits 60 without",
        "; ever reaching byte 0x8000; success exits 10 after W5=777.",
        "MV W0, #1",
        "MV W1, #15",
        "SHL W0, W0, W1",
        "JMPR W0",
        "MV W8, #60",
        "SYSCALL #2",
    ]
    lines += ["MV W2, #0"] * (8192 - 6)
    lines += [
        "MV W5, #777",
        "MV W8, #10",
        "SYSCALL #2",
    ]
    instrs = [ln for ln in lines if ln and not ln.startswith(";")]
    assert len(instrs) == 8195, len(instrs)
    assert instrs[8192] == "MV W5, #777"
    (HERE / "jmpr_range_discriminating.asm").write_text("\n".join(lines) + "\n")


def emit_control() -> None:
    lines = [
        "; F3-02 Q-D1 control: same 9-page image, no jump, sequential padding.",
        "; Reaches the marker by fall-through and exits 10.",
    ]
    lines += ["MV W2, #0"] * 8191
    lines += [
        "MV W5, #777",
        "MV W8, #10",
        "SYSCALL #2",
    ]
    instrs = [ln for ln in lines if ln and not ln.startswith(";")]
    assert len(instrs) == 8194, len(instrs)
    assert instrs[8191] == "MV W5, #777"
    (HERE / "jmpr_range_discriminating_control.asm").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    emit_probe()
    emit_control()
    print("wrote jmpr_range_discriminating.asm (8195 instructions, 32780 bytes)")
    print("wrote jmpr_range_discriminating_control.asm (8194 instructions, 32776 bytes)")
