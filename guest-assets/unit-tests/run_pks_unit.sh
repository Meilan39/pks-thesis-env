#!/usr/bin/env bash
# ==============================================================================
# guest-assets/unit-tests/run_pks_unit.sh - In-kernel PKS unit test runner
# ==============================================================================
# Runs Ira Weiny's built-in PKS debugfs test suite (CONFIG_PKS_TEST=y)
# ==============================================================================
set -u

RUN_PKS="/sys/kernel/debug/x86/run_pks"
RESULTS_DIR="${RESULTS_DIR:-/tmp/unit_results}"
mkdir -p "$RESULTS_DIR"

echo "================================================================"
echo " In-Kernel PKS Self-Test Suite (debugfs)"
echo "================================================================"

# 1. Ensure debugfs is mounted
if ! mountpoint -q /sys/kernel/debug; then
    mkdir -p /sys/kernel/debug
    mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
fi

if [ ! -f "$RUN_PKS" ]; then
    echo "[ERR]  DebugFS test interface not found at $RUN_PKS"
    echo "       Ensure kernel was built with CONFIG_PKS_TEST=y and CONFIG_DEBUG_FS=y"
    exit 1
fi

# 2. Enable dynamic debug for detailed test output if supported
if [ -f /sys/kernel/debug/dynamic_debug/control ]; then
    echo "file pks_test.c +pflm" > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
fi

TEST_DESCS=(
    [0]="Boot defaults & initial PKRS masks"
    [1]="Single-thread permission updates & fault gen"
    [2]="Context-switch register persistence (task 1)"
    [3]="Context-switch register persistence (task 2)"
)

echo ""
printf " %-6s | %-45s | %-8s\n" "Test" "Description" "Result"
printf "%s\n" "------------------------------------------------------------------"

TOTAL_PASS=0
TOTAL_TESTS=4

for test_id in 0 1 2 3; do
    desc="${TEST_DESCS[$test_id]}"
    dmesg_before=$(dmesg | wc -l)

    # Trigger test via debugfs write
    echo "$test_id" > "$RUN_PKS" 2>/dev/null
    rc=$?

    dmesg_after=$(dmesg | tail -n "+$((dmesg_before + 1))")
    echo "$dmesg_after" > "$RESULTS_DIR/test_${test_id}.log"

    # Evaluate test outcome from exit code and dmesg
    if [ $rc -eq 0 ] && ! echo "$dmesg_after" | grep -qi "FAIL"; then
        result="[PASS]"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        result="[FAIL]"
    fi

    printf " Test %-1s | %-45s | %-8s\n" "$test_id" "$desc" "$result"
done

printf "%s\n" "------------------------------------------------------------------"
echo " Summary: $TOTAL_PASS / $TOTAL_TESTS tests passed"
echo ""

# Persist output to protected partition if mounted
if mountpoint -q /mnt/protected; then
    mkdir -p /mnt/protected/unit_results
    cp -a "$RESULTS_DIR"/* /mnt/protected/unit_results/ 2>/dev/null || true
fi

if [ "$TOTAL_PASS" -eq "$TOTAL_TESTS" ]; then
    echo "[OK]   All PKS in-kernel unit tests passed successfully"
    exit 0
else
    echo "[WARN] One or more PKS unit tests failed or reported warnings"
    exit 1
fi
