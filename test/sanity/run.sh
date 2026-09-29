#!/usr/bin/env bash
# test/sanity/run.sh - PKS page-cache scoping checks; verdict from the [PASS]/
# [FAIL] lines the C harness prints off the debugfs scope counters.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; source "$ROOT/common.sh"
VAR="${1:-on}"; BIN="$DIR/pks_sanity_test"
[ -x "$BIN" ] || { [ -f "$DIR/pks_sanity_test.c" ] && gcc -O2 -Wall -o "$BIN" "$DIR/pks_sanity_test.c" 2>/dev/null || true; }
OUT="$DIR/raw/$VAR"; mkdir -p "$OUT" 2>/dev/null || true
LOG="$OUT/sanity.log"
if [ -x "$BIN" ]; then "$BIN" > "$LOG" 2>&1 || true; fi
p=$(grep -c '\[PASS\]' "$LOG" 2>/dev/null || echo 0)
f=$(grep -c '\[FAIL\]' "$LOG" 2>/dev/null || echo 0)
if [ "$p" -eq 0 ] && [ "$f" -eq 0 ]; then
    emit_status sanity "$VAR" FAIL note=no_output
elif [ "$f" -eq 0 ]; then
    emit_status sanity "$VAR" PASS passed="$p"
else
    emit_status sanity "$VAR" FAIL passed="$p" failed="$f"
fi
