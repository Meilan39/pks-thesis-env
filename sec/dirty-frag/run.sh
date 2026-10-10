#!/usr/bin/env bash
# ==============================================================================
# sec/dirty-frag/run.sh - Softirq/workqueue page-cache write neutralization
# ==============================================================================
# Builds the PoC if needed, seeds a marker in the protected victim file, drops
# caches to force a real page-cache re-fault, runs it as testuser, and reports
# whether the marker survived. Under on the asynchronous softirq store is
# suppressed via instruction-pointer advance (panic fallback on unhandled paths);
# under off the marker is overwritten.
# ==============================================================================
set -u

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------
TARGET_FILE="/mnt/protected/victim_file"
EXPLOIT_BIN="./exp"
EXPLOIT_SRC="./exp.c"
CLEAN_MARKER="PKS_CLEAN_MARKER_dirty-frag_DO_NOT_OVERWRITE"

# ------------------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ]    || { echo "error: root privileges required"; exit 1; }
id testuser &>/dev/null || { echo "error: testuser account required"; exit 1; }
[ -d "/mnt/protected" ] || { echo "error: /mnt/protected not mounted"; exit 1; }
[ -x "$EXPLOIT_BIN" ]   || gcc -O2 -Wall -pthread -o "$EXPLOIT_BIN" "$EXPLOIT_SRC" || { echo "error: build failed"; exit 1; }

# ------------------------------------------------------------------------------
# Prepare victim file
# ------------------------------------------------------------------------------
printf '%s\n' "$CLEAN_MARKER" > "$TARGET_FILE"
head -c 4096 /dev/zero >> "$TARGET_FILE" 2>/dev/null || true
chmod 644 "$TARGET_FILE"
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
cat "$TARGET_FILE" > /dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# Run exploit
# ------------------------------------------------------------------------------
su -s /bin/bash testuser -c "'$EXPLOIT_BIN'" || true

# ------------------------------------------------------------------------------
# Inspect marker
# ------------------------------------------------------------------------------
if grep -qF "$CLEAN_MARKER" <(head -c 256 "$TARGET_FILE" 2>/dev/null); then
    echo "marker=intact"
else
    echo "marker=altered"
fi
