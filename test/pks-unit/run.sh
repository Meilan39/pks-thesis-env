#!/usr/bin/env bash
# ==============================================================================
# test/pks-unit/run.sh - Upstream x86 PKS Architectural Selftest
# ==============================================================================
# Executes Intel's upstream kernel selftest (tools/testing/selftests/x86/test_pks)
# triggered via /sys/kernel/debug/x86/run_pks.
#
# Validates core hardware PKS capabilities:
# - Default key permissions (check_defaults)
# - Single key allocation and write protection (single)
# - Context switching across threads (context_switch)
# - Exception handling and fault callbacks (exception, exception_update)
#
# Keyed off userspace [OK] assertions and exit code 0. An intentional negative
# kernel test case ([6]: Unknown test) emits a FAIL line in dmesg, which is
# safely distinguished from userspace test failures.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/common.sh"

VARIANT="${1:-on}"
TEST_BIN="$SCRIPT_DIR/test_pks"
RUN_PKS_TRIGGER="/sys/kernel/debug/x86/run_pks"

# Compile test binary if absent
if [ ! -x "$TEST_BIN" ] && [ -f "$SCRIPT_DIR/test_pks.c" ]; then
    gcc -O2 -Wall -o "$TEST_BIN" "$SCRIPT_DIR/test_pks.c" -lpthread 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 1. Execute Upstream PKS Selftest
# ------------------------------------------------------------------------------
# Stream [RUN]/[OK]/[FAIL] straight to stdout -> serial -> test/raw-<variant>.log
# (captured by the axis runner); no redirect and no scratch file. stdbuf -oL keeps
# the lines live. test_pks exits nonzero iff any selftest failed (sticky-fail in
# run_all), so the exit code alone is the verdict.
test_rc=127
if [ -x "$TEST_BIN" ] && [ -e "$RUN_PKS_TRIGGER" ]; then
    stdbuf -oL -eL "$TEST_BIN" -d
    test_rc=$?
fi

# ------------------------------------------------------------------------------
# 2. Verdict Evaluation
# ------------------------------------------------------------------------------
# The binary's exit code is authoritative; the [RUN]/[OK]/[FAIL] detail is now in
# the raw transcript for auditing. (A debug build's intentional negative case
# [6]: Unknown test emits a dmesg FAIL that does not affect this userspace rc.)
if [ "$test_rc" -eq 0 ]; then
    emit_status pks-unit "$VARIANT" PASS
elif [ ! -e "$RUN_PKS_TRIGGER" ]; then
    emit_status pks-unit "$VARIANT" FAIL note=no_debugfs_trigger
else
    emit_status pks-unit "$VARIANT" FAIL rc="$test_rc"
fi
