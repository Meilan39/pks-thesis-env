#!/usr/bin/env bash
# test/pks-unit/run.sh - upstream x86 PKS architectural selftest via the debugfs
# trigger; verdict from exit code + absence of failure markers in its output.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; source "$ROOT/common.sh"
VAR="${1:-on}"; BIN="$DIR/test_pks"; RUN_PKS="/sys/kernel/debug/x86/run_pks"
[ -x "$BIN" ] || { [ -f "$DIR/test_pks.c" ] && gcc -O2 -Wall -o "$BIN" "$DIR/test_pks.c" -lpthread 2>/dev/null || true; }
OUT="$DIR/raw/$VAR"; mkdir -p "$OUT" 2>/dev/null || true
LOG="$OUT/pks-unit.log"; rc=127
if [ -x "$BIN" ] && [ -e "$RUN_PKS" ]; then "$BIN" -d > "$LOG" 2>&1; rc=$?; fi
# Key the verdict off the harness's explicit result line, not a loose "fail"
# match (its banner prints benign strings like "last test FAIL").
if [ "$rc" -eq 0 ] && grep -qE 'Test complete.*PASS' "$LOG" 2>/dev/null \
   && ! grep -qE 'Test complete.*FAIL|\[FAIL\]' "$LOG" 2>/dev/null; then
    emit_status pks-unit "$VAR" PASS
elif [ ! -e "$RUN_PKS" ]; then
    emit_status pks-unit "$VAR" FAIL note=no_debugfs_trigger
else
    emit_status pks-unit "$VAR" FAIL rc="$rc"
fi
