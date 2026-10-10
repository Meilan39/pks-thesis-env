#!/usr/bin/env bash
# ==============================================================================
# test/pks-unit/run.sh - Upstream x86 PKS architectural selftest
# ==============================================================================
# Runs Intel's tools/testing/selftests/x86/test_pks via /sys/kernel/debug/x86/
# run_pks: default-key perms, allocation/write-protect, context switching, and
# exception/fault-callback handling. test_pks exits nonzero iff any case failed
# (sticky-fail in run_all), so its exit code is the verdict.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/common.sh"

VARIANT="${1:-on}"
TEST_BIN="$SCRIPT_DIR/test_pks"
RUN_PKS_TRIGGER="/sys/kernel/debug/x86/run_pks"

# Compile if missing or stale
if [ -f "$SCRIPT_DIR/test_pks.c" ] \
    && { [ ! -x "$TEST_BIN" ] || [ "$SCRIPT_DIR/test_pks.c" -nt "$TEST_BIN" ]; }; then
    gcc -O2 -Wall -o "$TEST_BIN" "$SCRIPT_DIR/test_pks.c" -lpthread 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# Execute selftest
# ------------------------------------------------------------------------------
# Stream [RUN]/[OK]/[FAIL] straight to serial (captured by the axis runner); no
# redirect, no scratch file. stdbuf -oL keeps the lines live.
test_rc=127
if [ -x "$TEST_BIN" ] && [ -e "$RUN_PKS_TRIGGER" ]; then
    stdbuf -oL -eL "$TEST_BIN" -d
    test_rc=$?
fi

# ------------------------------------------------------------------------------
# Resolve verdict
# ------------------------------------------------------------------------------
# A debug build's intentional negative case ([6]: Unknown test) emits a dmesg
# FAIL that does not affect this userspace rc.
if [ "$test_rc" -eq 0 ]; then
    emit_status pks-unit "$VARIANT" PASS
elif [ ! -e "$RUN_PKS_TRIGGER" ]; then
    emit_status pks-unit "$VARIANT" FAIL note=no_debugfs_trigger
else
    emit_status pks-unit "$VARIANT" FAIL rc="$test_rc"
fi
