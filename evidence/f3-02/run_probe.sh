#!/usr/bin/env bash
# Reproducible driver for the F3-02 probes through the zepa-machine TUI.
#
# Paths are resolved from the repository root and from MACHINE_WT, so no
# per-user absolute path is needed:
#
#   export ZESH_ROOT=$(git rev-parse --show-toplevel)
#   export MACHINE_WT=${MACHINE_WT:-/tmp/opencode/zepa-machine-e8fd798}
#   export KERNEL_BIN=${KERNEL_BIN:-$MACHINE_WT/zepa-kernel-e8fd798}
#
# Usage:
#   run_probe.sh build                 build the pinned kernel TUI
#   run_probe.sh start                 start tmux session and wait for boot
#   run_probe.sh copy <probe>          copy probe into $MACHINE_WT/evidence-probes
#   run_probe.sh run <probe>           copy + send `input evidence-probes/<probe>`
#   run_probe.sh cmd "<text>"          send a command line
#   run_probe.sh wait "<pattern>" [n]  wait for pattern (n * 0.5 s)
#   run_probe.sh cap                   print `tmux capture-pane -p`
#   run_probe.sh stop                  kill the session
#
# `<probe>` is a file name in $ZESH_ROOT/evidence/f3-02/.
set -uo pipefail

ZESH_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$ZESH_ROOT" ]; then
  echo "run_probe.sh: run from inside a zesh checkout" >&2
  exit 2
fi
EVIDENCE_DIR=$ZESH_ROOT/evidence/f3-02
MACHINE_WT=${MACHINE_WT:-/tmp/opencode/zepa-machine-e8fd798}
KERNEL_BIN=${KERNEL_BIN:-$MACHINE_WT/zepa-kernel-e8fd798}
SESSION=${SESSION:-zepa-spike}
LOG=${LOG:-$MACHINE_WT/zepa-kernel.log}

usage() {
  sed -n '11,21p' "$0"
}

require_machine() {
  if [ ! -x "$KERNEL_BIN" ]; then
    echo "run_probe.sh: missing kernel binary $KERNEL_BIN (run: run_probe.sh build)" >&2
    exit 2
  fi
}

copy_probe() {
  probe=${1:-}
  if [ -z "$probe" ] || [ ! -f "$EVIDENCE_DIR/$probe" ]; then
    echo "run_probe.sh: no such probe: ${probe:-<empty>} (looked in $EVIDENCE_DIR)" >&2
    return 2
  fi
  mkdir -p "$MACHINE_WT/evidence-probes"
  cp "$EVIDENCE_DIR/$probe" "$MACHINE_WT/evidence-probes/$probe"
  echo "evidence-probes/$probe"
}

case "${1:-}" in
build)
  if [ ! -d "$MACHINE_WT" ]; then
    echo "run_probe.sh: MACHINE_WT does not exist: $MACHINE_WT" >&2
    exit 2
  fi
  ( cd "$MACHINE_WT" && go build -tags kernel -o "$KERNEL_BIN" . )
  ;;
start)
  require_machine
  tmux kill-session -t "$SESSION" 2>/dev/null
  tmux new-session -d -s "$SESSION" -x 220 -y 55 \
    "cd '$MACHINE_WT' && '$KERNEL_BIN' 2GB 128 2>&1 | tee '$LOG'"
  sleep 3
  tmux send-keys -t "$SESSION" 'b 300' Enter
  for _ in $(seq 1 40); do
    if tmux capture-pane -t "$SESSION" -p 2>/dev/null | grep -q 'Breakpoint reached'; then
      echo "boot ok: $(tmux capture-pane -t "$SESSION" -p | grep 'Breakpoint reached' | tr -s ' ')"
      exit 0
    fi
    sleep 0.5
  done
  echo "boot timeout" >&2
  tmux capture-pane -t "$SESSION" -p | tail -5
  exit 1
  ;;
copy)
  copy_probe "${2:-}"
  ;;
run)
  require_machine
  probe=${2:-}
  rel=$(copy_probe "$probe") || exit $?
  tmux send-keys -t "$SESSION" "input $rel" Enter
  sleep 0.4
  ;;
cmd)
  tmux send-keys -t "$SESSION" "$2" Enter
  sleep 0.4
  ;;
wait)
  pat=${2:-}
  tries=${3:-60}
  if [ -z "$pat" ]; then
    echo "run_probe.sh: wait needs a pattern" >&2
    exit 2
  fi
  for _ in $(seq 1 "$tries"); do
    if tmux capture-pane -t "$SESSION" -p 2>/dev/null | grep -q "$pat"; then exit 0; fi
    sleep 0.5
  done
  echo "timeout waiting for: $pat" >&2
  exit 1
  ;;
cap)
  tmux capture-pane -t "$SESSION" -p
  ;;
stop)
  tmux kill-session -t "$SESSION" 2>/dev/null
  ;;
*)
  usage
  exit 2
  ;;
esac
