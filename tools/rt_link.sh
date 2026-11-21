#!/usr/bin/env bash
# Link a test or program with rt/rt.asm by concatenation (the assembler has no
# include). The caller's source comes first so its first instruction is the
# image entry at VA 0.
#
# Usage: tools/rt_link.sh <source.asm> [<out.asm>]
# Default output: build/<basename of source>
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
src=${1:?usage: tools/rt_link.sh <source.asm> [<out.asm>]}
out=${2:-$root/build/$(basename "$src")}

mkdir -p "$(dirname "$out")"
{
    cat "$src"
    printf '\n; ---- linked: rt/rt.asm ----\n'
    cat "$root/rt/rt.asm"
} > "$out"
echo "$out"
