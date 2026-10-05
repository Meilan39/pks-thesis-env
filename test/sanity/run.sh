#!/usr/bin/env bash
# ==============================================================================
# test/sanity/run.sh - PKS Page-Cache Scoping and Subsystem Sanity Test
# ==============================================================================
# Validates in-kernel PKS page-cache protection invariants:
# 1. VFS system call write scoping (write, pwrite, writev, ftruncate, fallocate)
# 2. Static pool page-cache residency (PFN bounds verification via /proc/self/pagemap)
# 3. Fail-closed policy enforcement (rejection of mmap(PROT_WRITE) and O_DIRECT)
#
# These invariants hold ONLY when pcache_pks=on with the protected mount active.
# Under off/control, the PKS pool is inactive, so the checks are not applicable.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/common.sh"

VARIANT="${1:-on}"
SANITY_BIN="$SCRIPT_DIR/pks_sanity_test"

# Sanity assertions apply strictly to PKS-enabled mode
if [ "$VARIANT" != "on" ]; then
    emit_status sanity "$VARIANT" PASS note=not_applicable_when_off
    exit 0
fi

# Compile sanity harness if absent
if [ ! -x "$SANITY_BIN" ] && [ -f "$SCRIPT_DIR/pks_sanity_test.c" ]; then
    gcc -O2 -Wall -o "$SANITY_BIN" "$SCRIPT_DIR/pks_sanity_test.c" 2>/dev/null || true
fi

LOG_FILE="/tmp/sanity_${VARIANT}.log"

# ------------------------------------------------------------------------------
# 1. Execute Sanity Test Suite
# ------------------------------------------------------------------------------
if [ -x "$SANITY_BIN" ]; then
    "$SANITY_BIN" > "$LOG_FILE" 2>&1 || true
fi

# ------------------------------------------------------------------------------
# 2. Verdict Evaluation
# ------------------------------------------------------------------------------
pass_count=$(grep -c '\[PASS\]' "$LOG_FILE" 2>/dev/null || echo 0)
fail_count=$(grep -c '\[FAIL\]' "$LOG_FILE" 2>/dev/null || echo 0)

if [ "$pass_count" -eq 0 ] && [ "$fail_count" -eq 0 ]; then
    emit_status sanity "$VARIANT" FAIL note=no_output
elif [ "$fail_count" -eq 0 ]; then
    emit_status sanity "$VARIANT" PASS passed="$pass_count"
else
    emit_status sanity "$VARIANT" FAIL passed="$pass_count" failed="$fail_count"
fi
