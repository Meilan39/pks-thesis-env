#!/usr/bin/env bash
# sec/copy-fail/run.sh - CVE-2026-31431 AF_ALG splice. Syscall context, so under
# PKS the stray write is trapped as -EFAULT and the VM survives to self-report.
# Verdict is the CAUSAL comparison of the victim marker before vs after.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; source "$ROOT/common.sh"
VAR="${1:-on}"; EXP="$DIR/exp"
TGT=/mnt/protected; [ -d "$TGT" ] || TGT=/tmp
VICTIM="$TGT/victim_file"; MARK="PKS_CLEAN_MARKER_31431_DO_NOT_OVERWRITE"
OUT="$DIR/raw/$VAR"; mkdir -p "$OUT" 2>/dev/null || true; LOG="$OUT/copy-fail.log"

printf '%s\n' "$MARK" > "$VICTIM"; sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
emit_status copy-fail "$VAR" PENDING phase=pre_trigger   # safety net should it panic
erc=0
if [ -f "$EXP" ]; then python3 "$EXP" "$VICTIM" > "$LOG" 2>&1; erc=$?; else erc=127; fi
# Read back WITHOUT dropping caches: the exploit corrupts the in-memory
# page-cache page, which may never be written to disk. Dropping caches here
# would evict the corruption and re-read the clean on-disk marker (false PASS).
after="$(head -c 256 "$VICTIM" 2>/dev/null)"

if printf '%s' "$after" | grep -qF "$MARK"; then
    if [ "$VAR" = on ]; then emit_status copy-fail "$VAR" NEUTRALIZED marker=intact rc="$erc" note=trapped
    else                     emit_status copy-fail "$VAR" FAIL marker=intact note=baseline_not_corrupted rc="$erc"; fi
else
    emit_status copy-fail "$VAR" VULNERABLE marker=altered rc="$erc"
fi
