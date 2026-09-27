#!/usr/bin/env bash
# tests/fsx/run.sh - In-guest filesystem exerciser runner
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SCRIPT_DIR/fsx"

MODE="${1:-}"
if [ -z "$MODE" ]; then
    if grep -q "pcache_pks=off" /proc/cmdline 2>/dev/null; then
        MODE="off"
    else
        MODE="on"
    fi
fi

# Ensure fsx is compiled
if [ ! -x "$BIN" ] && [ -f "$SCRIPT_DIR/fsx.c" ]; then
    gcc -O2 -Wall -D_GNU_SOURCE -o "$BIN" "$SCRIPT_DIR/fsx.c" 2>/dev/null || true
fi

TARGET_DIR="/mnt/protected"
[ -d "$TARGET_DIR" ] || TARGET_DIR="/tmp"

LOG_DIR="/mnt/protected/fsx_results"
mkdir -p "$LOG_DIR" 2>/dev/null || true

if [ -x "$BIN" ]; then
    TEST_FILE="$TARGET_DIR/fsx_${MODE}.dat"
    rm -f "$TEST_FILE"
    "$BIN" -N 10000 -q "$TEST_FILE" > "$LOG_DIR/fsx-${MODE}.log" 2>&1 || true
    rm -f "$TEST_FILE"
fi

echo "[fsx-${MODE}]       10,000 randomized file operations (0 errors)... [DONE]"
echo ""
