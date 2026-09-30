#!/usr/bin/env bash
# sec/fragnesia/run.sh - softirq/workqueue context. Under PKS the stray write takes
# an unhandled supervisor fault and the kernel PANICS (fail-closed); the guest
# will not return here, so the PENDING line + the host's classify_sec (which
# reads the panic + PKS-active signatures from the serial transcript) resolve
# the verdict. If it instead survives, the marker comparison decides.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; source "$ROOT/common.sh"
VAR="${1:-on}"; BIN="$DIR/exp"
[ -x "$BIN" ] || { [ -f "$DIR/exp.c" ] && gcc -O2 -Wall -pthread -o "$BIN" "$DIR/exp.c" 2>/dev/null || true; }
TGT=/mnt/protected; [ -d "$TGT" ] || TGT=/tmp
VICTIM="$TGT/victim_file"; MARK="PKS_CLEAN_MARKER_fragnesia_DO_NOT_OVERWRITE"
OUT="$DIR/raw/$VAR"; mkdir -p "$OUT" 2>/dev/null || true; LOG="$OUT/fragnesia.log"

printf '%s\n' "$MARK" > "$VICTIM"; sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
emit_status fragnesia "$VAR" PENDING phase=pre_trigger   # panic under 'on' -> host resolves
if [ -x "$BIN" ]; then "$BIN" > "$LOG" 2>&1 || true; fi   # may never return
# Read back WITHOUT dropping caches (page-cache corruption lives in memory).
after="$(head -c 256 "$VICTIM" 2>/dev/null)"

if printf '%s' "$after" | grep -qF "$MARK"; then
    if [ "$VAR" = on ]; then emit_status fragnesia "$VAR" NEUTRALIZED marker=intact note=trapped
    else                     emit_status fragnesia "$VAR" FAIL marker=intact note=baseline_not_corrupted; fi
else
    emit_status fragnesia "$VAR" VULNERABLE marker=altered
fi
