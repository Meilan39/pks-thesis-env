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

LOG_FILE="/tmp/pks-unit_${VARIANT}.log"

# ------------------------------------------------------------------------------
# 1. Execute Upstream PKS Selftest
# ------------------------------------------------------------------------------
# Execute selftest; userspace exit code and assertions reflect pass/fail
test_rc=127
if [ -x "$TEST_BIN" ] && [ -e "$RUN_PKS_TRIGGER" ]; then
    "$TEST_BIN" -d > "$LOG_FILE" 2>&1
    test_rc=$?
fi

# ------------------------------------------------------------------------------
# 2. Verdict Evaluation
# ------------------------------------------------------------------------------
# Userspace [OK] assertions and binary exit code 0 indicate test suite pass.
# An intentional negative kernel test case ([6]: Unknown test) emits a FAIL line
# in dmesg, which is safely distinguished from userspace test failures.
if [ "$test_rc" -eq 0 ] && grep -q '\[OK\]' "$LOG_FILE" 2>/dev/null; then
    emit_status pks-unit "$VARIANT" PASS
elif [ ! -e "$RUN_PKS_TRIGGER" ]; then
    emit_status pks-unit "$VARIANT" FAIL note=no_debugfs_trigger
else
    emit_status pks-unit "$VARIANT" FAIL rc="$test_rc"
fi
