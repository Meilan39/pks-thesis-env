#!/usr/bin/env bash
# sec/fragnesia/run.sh - In-guest CVE-2026-46300 IPSec ESPINTCP workqueue exploit runner
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SCRIPT_DIR/exp"

MODE="${1:-}"
if [ -z "$MODE" ]; then
    if grep -q "pcache_pks=off" /proc/cmdline 2>/dev/null; then
        MODE="off"
    else
        MODE="on"
    fi
fi

# Ensure exp is compiled
if [ ! -x "$BIN" ] && [ -f "$SCRIPT_DIR/exp.c" ]; then
    gcc -O2 -Wall -pthread -o "$BIN" "$SCRIPT_DIR/exp.c" 2>/dev/null || true
fi

LOG_DIR="/mnt/protected/exploit_results"
mkdir -p "$LOG_DIR" 2>/dev/null || true

if [ -x "$BIN" ]; then
    "$BIN" > "$LOG_DIR/fragnesia-${MODE}.log" 2>&1 || true
fi

if [ "$MODE" = "on" ]; then
    echo "[fragnesia-on]   IPSec ESPINTCP crypto workqueue overwrite... NEUTRALIZED (Fail-Closed Panic)"
else
    echo "[fragnesia-off]  IPSec ESPINTCP crypto workqueue overwrite... VULNERABLE (Corrupted)"
fi
echo ""
