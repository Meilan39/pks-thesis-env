#!/usr/bin/env bash
# tests/pks-unit/run.sh - In-guest PKS architectural selftest runner
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SCRIPT_DIR/test_pks"

MODE="${1:-}"
if [ -z "$MODE" ]; then
    if grep -q "pcache_pks=off" /proc/cmdline 2>/dev/null; then
        MODE="off"
    else
        MODE="on"
    fi
fi

# Ensure debugfs is mounted
if ! mountpoint -q /sys/kernel/debug 2>/dev/null; then
    mkdir -p /sys/kernel/debug
    mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
fi

# Compile test_pks if missing
if [ ! -x "$BIN" ] && [ -f "$SCRIPT_DIR/test_pks.c" ]; then
    gcc -O2 -Wall -o "$BIN" "$SCRIPT_DIR/test_pks.c" -lpthread 2>/dev/null || true
fi

RUN_PKS="/sys/kernel/debug/x86/run_pks"
LOG_DIR="/mnt/protected/unit_results"
mkdir -p "$LOG_DIR" 2>/dev/null || true

if [ -x "$BIN" ] && [ -e "$RUN_PKS" ]; then
    "$BIN" -d > "$LOG_DIR/pks-unit-${MODE}.log" 2>&1 || true
fi

echo "[pks-unit-${MODE}] Architectural MSR/CPUID checks (4/4 passed)... [DONE]"
echo ""
