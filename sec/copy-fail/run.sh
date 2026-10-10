#!/usr/bin/env bash
# ==============================================================================
# sec/copy-fail/run.sh - Syscall-Context Page-Cache Write Neutralization
# ==============================================================================
# Writes a unique marker into the protected victim file, drops caches to force a
# real page-cache re-fault, runs the unprivileged PoC as testuser, and reports
# whether the marker survived. Under pcache_pks=on the offending store is trapped
# in syscall context (returns -EFAULT) and the marker stays intact; under off it
# is overwritten. The host aggregator (sec/run.sh) turns the emitted marker line
# into a verdict.
# ==============================================================================
set -u

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# ------------------------------------------------------------------------------
# 1. Static Constants
# ------------------------------------------------------------------------------
TARGET_FILE="/mnt/protected/victim_file"
EXPLOIT_BIN="./exp"
CLEAN_MARKER="PKS_CLEAN_MARKER_31431_DO_NOT_OVERWRITE"

# ------------------------------------------------------------------------------
# 2. Precondition Checks
# ------------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ]    || { echo "error: root privileges required"; exit 1; }
id testuser &>/dev/null || { echo "error: testuser account required"; exit 1; }
[ -d "/mnt/protected" ] || { echo "error: /mnt/protected not mounted"; exit 1; }
[ -f "$EXPLOIT_BIN" ]   || { echo "error: $EXPLOIT_BIN not found"; exit 1; }

# ------------------------------------------------------------------------------
# 3. Target Preparation
# ------------------------------------------------------------------------------
printf '%s\n' "$CLEAN_MARKER" > "$TARGET_FILE"
chmod 644 "$TARGET_FILE"
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. Exploit Execution
# ------------------------------------------------------------------------------
# python3 -u forces unbuffered stdout/stderr so the PoC's diagnostics reach the
# serial transcript: under pcache_pks=on this task is SIGKILLed by the fault
# callback mid-run, and block-buffered output (pipe to journald, not a tty) would
# otherwise be discarded before any flush.
su -s /bin/bash testuser -c "python3 -u '$EXPLOIT_BIN'" || true

# ------------------------------------------------------------------------------
# 5. Marker Inspection
# ------------------------------------------------------------------------------
if grep -qF "$CLEAN_MARKER" <(head -c 256 "$TARGET_FILE" 2>/dev/null); then
    echo "marker=intact"
else
    echo "marker=altered"
fi
