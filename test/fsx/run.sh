#!/usr/bin/env bash
# test/fsx/run.sh - 10k randomized filesystem operations; verdict from fsx's own
# exit code and output (fsx aborts nonzero on any data-integrity mismatch).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; source "$ROOT/common.sh"
VAR="${1:-on}"; BIN="$DIR/fsx"
[ -x "$BIN" ] || { [ -f "$DIR/fsx.c" ] && gcc -O2 -Wall -D_GNU_SOURCE -o "$BIN" "$DIR/fsx.c" 2>/dev/null || true; }
TGT=/mnt/protected; [ -d "$TGT" ] || TGT=/tmp
OUT="$ROOT/results/raw/json/$VAR"; mkdir -p "$OUT" 2>/dev/null || true
LOG="$OUT/fsx.log"; F="$TGT/fsx_${VAR}.dat"; rm -f "$F"
rc=0
if [ -x "$BIN" ]; then "$BIN" -N 10000 -q "$F" > "$LOG" 2>&1; rc=$?; else rc=127; fi
rm -f "$F"
if [ "$rc" -eq 0 ] && ! grep -qiE 'error|bad data|mismatch|failed' "$LOG" 2>/dev/null; then
    emit_status fsx "$VAR" PASS ops=10000 errors=0
else
    emit_status fsx "$VAR" FAIL rc="$rc" errors="$(grep -ciE 'error|bad data|mismatch' "$LOG" 2>/dev/null || echo 1)"
fi
