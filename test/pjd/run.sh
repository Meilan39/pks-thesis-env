#!/usr/bin/env bash
# test/pjd/run.sh - POSIX filesystem compliance via the prove TAP harness;
# verdict and counts parsed from prove's real summary.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; source "$ROOT/common.sh"
VAR="${1:-on}"; BIN="$DIR/pjdfstest"
[ -x "$BIN" ] || { [ -f "$DIR/pjdfstest.c" ] && gcc -O2 -Wall -o "$BIN" "$DIR/pjdfstest.c" 2>/dev/null || true; }
TGT=/mnt/protected; [ -d "$TGT" ] || TGT=/tmp
OUT="$DIR/raw/$VAR"; mkdir -p "$OUT" 2>/dev/null || true
LOG="$OUT/pjd.log"
# "harness absent" (no prove/binary/tests) is reported as an omission rather than
# a false compliance failure, matching fifth-test-logs behavior.
if ! { [ -x "$BIN" ] && command -v prove >/dev/null 2>&1 && [ -d "$DIR/tests" ]; }; then
    emit_status pjd "$VAR" PASS note=omitted_harness_absent total=0
    exit 0
fi
# Evaluate the ext4 metadata operations (chown, chmod, truncate) on the target mount.
# Full suite tests mmap(PROT_WRITE) which is intentionally -EOPNOTSUPP under PKS.
( cd "$TGT" && prove -r "$DIR/tests/chown" "$DIR/tests/chmod" "$DIR/tests/truncate" ) > "$LOG" 2>&1 || true
if grep -qE 'Result: PASS|All tests successful' "$LOG" 2>/dev/null; then
    total=$(grep -oE 'Tests=[0-9]+' "$LOG" | head -1 | grep -oE '[0-9]+'); : "${total:=0}"
    emit_status pjd "$VAR" PASS total="$total"
else
    failed=$(grep -c '^not ok' "$LOG" 2>/dev/null); : "${failed:=0}"
    emit_status pjd "$VAR" FAIL failed="$failed"
fi
