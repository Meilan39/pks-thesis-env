#!/usr/bin/env bash
# ==============================================================================
# sec/copy-fail/run.sh - Syscall-context page-cache write neutralization
# ==============================================================================
# Seeds a marker in the protected victim file, drops caches to force a real
# page-cache re-fault, runs the unprivileged PoC as testuser, and reports whether
# the marker survived. Under on the store is trapped in syscall context (-EFAULT)
# and the marker stays intact; under off it is overwritten. sec/run.sh turns the
# emitted marker line into the verdict.
# ==============================================================================
set -u

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------
TARGET_FILE="/mnt/protected/victim_file"
EXPLOIT_BIN="./exp"
CLEAN_MARKER="PKS_CLEAN_MARKER_31431_DO_NOT_OVERWRITE"

# ------------------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ]    || { echo "error: root privileges required"; exit 1; }
id testuser &>/dev/null || { echo "error: testuser account required"; exit 1; }
[ -d "/mnt/protected" ] || { echo "error: /mnt/protected not mounted"; exit 1; }
[ -f "$EXPLOIT_BIN" ]   || { echo "error: $EXPLOIT_BIN not found"; exit 1; }

# ------------------------------------------------------------------------------
# Prepare victim file
# ------------------------------------------------------------------------------
printf '%s\n' "$CLEAN_MARKER" > "$TARGET_FILE"
chmod 644 "$TARGET_FILE"
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

# ------------------------------------------------------------------------------
# Run exploit
# ------------------------------------------------------------------------------
# python3 -u keeps stdout/stderr unbuffered so the PoC's diagnostics reach the
# transcript: under pcache_pks=on this task is SIGKILLed mid-run, and buffered
# output (piped to journald) would be discarded before any flush.
su -s /bin/bash testuser -c "python3 -u '$EXPLOIT_BIN'" || true

# ------------------------------------------------------------------------------
# Inspect marker
# ------------------------------------------------------------------------------
if grep -qF "$CLEAN_MARKER" <(head -c 256 "$TARGET_FILE" 2>/dev/null); then
    echo "marker=intact"
else
    echo "marker=altered"
fi
