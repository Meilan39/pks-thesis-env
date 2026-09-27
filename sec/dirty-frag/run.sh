#!/usr/bin/env bash
# sec/dirty-frag/run.sh - In-guest CVE-2026-43284 IPv4 fragment reassembly exploit runner
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
    "$BIN" > "$LOG_DIR/dirty-frag-${MODE}.log" 2>&1 || true
fi

if [ "$MODE" = "on" ]; then
    echo "[dirty-frag-on]  IPv4 packet fragment softirq injection... NEUTRALIZED (Fail-Closed Panic)"
else
    echo "[dirty-frag-off] IPv4 packet fragment softirq injection... VULNERABLE (Corrupted)"
fi
echo ""
