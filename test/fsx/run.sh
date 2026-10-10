#!/usr/bin/env bash
# ==============================================================================
# test/fsx/run.sh - Randomized filesystem exerciser (fsx), 10,000 ops
# ==============================================================================
# fsx aborts nonzero on any data mismatch, so its exit code is authoritative.
# Under PKS 'on', writable mmap is rejected (-EOPNOTSUPP), so -W drops MAPWRITE.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/common.sh"

VARIANT="${1:-on}"
FSX_BIN="$SCRIPT_DIR/fsx"

# Compile if missing or stale
if [ ! -x "$FSX_BIN" ] || [ "$SCRIPT_DIR/fsx.c" -nt "$FSX_BIN" ]; then
    gcc -O2 -Wall -D_GNU_SOURCE -o "$FSX_BIN" "$SCRIPT_DIR/fsx.c" 2>/dev/null || true
fi

# Protected mount, or /tmp if absent
TARGET_DIR="/mnt/protected"
if [ ! -d "$TARGET_DIR" ]; then
    TARGET_DIR="/tmp"
fi

LOG_FILE="/tmp/fsx_${VARIANT}.log"
TEST_FILE="$TARGET_DIR/fsx_${VARIANT}.dat"
rm -f "$TEST_FILE"

# Op count (override with FSX_NUM_OPS)
NUM_OPS="${FSX_NUM_OPS:-10000}"

# -W drops MAPWRITE under PKS, where writable mmap is rejected
EXTRA_FLAGS=""
if [ "$VARIANT" = "on" ]; then
    EXTRA_FLAGS="-W"
fi

# ------------------------------------------------------------------------------
# Execute fsx stress run
# ------------------------------------------------------------------------------
fsx_rc=0
if [ -x "$FSX_BIN" ]; then
    "$FSX_BIN" -N "$NUM_OPS" $EXTRA_FLAGS "$TEST_FILE" > "$LOG_FILE" 2>&1 || fsx_rc=$?
else
    fsx_rc=127
fi

rm -f "$TEST_FILE"

# ------------------------------------------------------------------------------
# Resolve verdict
# ------------------------------------------------------------------------------
if [ "$fsx_rc" -eq 127 ]; then
    emit_status fsx "$VARIANT" FAIL note=harness_absent
elif [ "$fsx_rc" -eq 0 ] && ! grep -qiE 'FATAL CORRUPTION|CORRUPTION DETECTED' "$LOG_FILE" 2>/dev/null; then
    emit_status fsx "$VARIANT" PASS ops="$NUM_OPS" errors=0
else
    emit_status fsx "$VARIANT" FAIL rc="$fsx_rc"
fi

rm -f "$LOG_FILE"
