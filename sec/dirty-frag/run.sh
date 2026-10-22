#!/usr/bin/env bash
# ==============================================================================
# sec/dirty-frag/run.sh - Softirq/workqueue page-cache write neutralization
# ==============================================================================
# Builds the PoC if needed, seeds a marker in the protected victim file, drops
# caches to force a real page-cache re-fault, runs it as testuser, and reports
# whether the marker survived. Under on each asynchronous softirq store is
# suppressed by advancing the instruction pointer past it, without crashing the
# system; under off the marker is overwritten.
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
# Verify the seed BEFORE attacking (see sec/fragnesia/run.sh for the shared-file
# rationale): a failed or stale re-seed is a harness fault, never "altered".
# ------------------------------------------------------------------------------
if ! grep -qF "$CLEAN_MARKER" <(head -c 256 "$TARGET_FILE" 2>/dev/null); then
    echo "seed=failed"
    echo "marker=unresolved"
    exit 1
fi
echo "seed=ok"

# ------------------------------------------------------------------------------
# Run exploit
# ------------------------------------------------------------------------------
su -s /bin/bash testuser -c "'$EXPLOIT_BIN'" || true

# ------------------------------------------------------------------------------
# Inspect marker (record the bytes so a verdict is never a bare word)
# ------------------------------------------------------------------------------
echo "[evidence] dirty-frag victim first 64 bytes after exploit:"
head -c 64 "$TARGET_FILE" 2>/dev/null | od -An -tx1 || true
if grep -qF "$CLEAN_MARKER" <(head -c 256 "$TARGET_FILE" 2>/dev/null); then
    echo "marker=intact"
else
    echo "marker=altered"
fi
