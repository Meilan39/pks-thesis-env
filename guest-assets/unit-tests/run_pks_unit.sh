#!/usr/bin/env bash
# ==============================================================================
# guest-assets/unit-tests/run_pks_unit.sh - In-kernel PKS unit test runner
# ==============================================================================
# Runs Ira Weiny's built-in PKS debugfs test suite (CONFIG_PKS_TEST=y)
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_PKS="/sys/kernel/debug/x86/run_pks"
TEST_PKS_BIN="$SCRIPT_DIR/test_pks"
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

if [ ! -e "$RUN_PKS" ]; then
    echo "[ERR]  DebugFS test interface not found at $RUN_PKS"
    echo "       Ensure kernel was built with CONFIG_PKS_TEST=y and CONFIG_DEBUG_FS=y"
    echo "       and that CPU supports PKS (CR4.PKS)."
    exit 1
fi

# 2. Enable dynamic debug for detailed test output if supported
if [ -f /sys/kernel/debug/dynamic_debug/control ]; then
    echo "file pks_test.c +pflm" > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
    echo "file pkeys.c +pflm" > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
fi

SANITY_BIN="$SCRIPT_DIR/pks_sanity_test"
if [ -f "$SCRIPT_DIR/pks_sanity_test.c" ] && { [ ! -x "$SANITY_BIN" ] || [ "$SCRIPT_DIR/pks_sanity_test.c" -nt "$SANITY_BIN" ]; }; then
    echo "[INFO] Compiling pks_sanity_test..."
    gcc -O2 -Wall -o "$SANITY_BIN" "$SCRIPT_DIR/pks_sanity_test.c" 2>/dev/null || true
fi

SANITY_RC=0
if [ -x "$SANITY_BIN" ]; then
    echo ""
    "$SANITY_BIN" | tee "$RESULTS_DIR/pks_sanity.log"
    SANITY_RC=${PIPESTATUS[0]}
fi

# 3. If compiled selftest binary exists, run it
if [ -x "$TEST_PKS_BIN" ]; then
    echo "[INFO] Running upstream compiled test_pks selftest..."
    "$TEST_PKS_BIN" -d | tee "$RESULTS_DIR/test_pks.log"
    SELRUN_RC=${PIPESTATUS[0]}
    echo ""
    echo "--- Kernel Debug Log (dmesg) ---"
    dmesg | grep -E "(pks|pkeys|PKS|pkrs)" | tail -n 30 || true
    echo "--------------------------------"
    
    if mountpoint -q /mnt/protected; then
        mkdir -p /mnt/protected/unit_results
        cp -a "$RESULTS_DIR"/* /mnt/protected/unit_results/ 2>/dev/null || true
    fi

    TOTAL_RC=$((SANITY_RC | SELRUN_RC))
    if [ "$TOTAL_RC" -eq 0 ]; then
        echo "[OK]   All PKS unit & sanity tests passed successfully"
        exit 0
    else
        echo "[WARN] One or more PKS unit/sanity tests failed (rc=$TOTAL_RC)"
        exit 1
    fi
fi

# Fallback: shell-based execution using persistent file descriptors
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

# Open persistent read-write file descriptor 3 to /sys/kernel/debug/x86/run_pks
exec 3<>"$RUN_PKS"

for test_id in 0 1 2 3; do
    desc="${TEST_DESCS[$test_id]}"
    dmesg_before=$(dmesg | wc -l)

    # Write test ID to open file descriptor
    echo "$test_id" >&3
    rc=$?

    # Read back result string ("PASS\n" or "FAIL\n") from debugfs
    res_str=""
    read -t 2 -u 3 res_str || res_str=""

    dmesg_after=$(dmesg | tail -n "+$((dmesg_before + 1))")
    echo "$dmesg_after" > "$RESULTS_DIR/test_${test_id}.log"

    if [ "$res_str" = "PASS" ] || ([ $rc -eq 0 ] && [ -n "$res_str" ] && ! echo "$dmesg_after" | grep -qi "FAIL"); then
        result="[PASS]"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        result="[FAIL]"
        echo "   [DEBUG] Test $test_id returned: '$res_str' (rc=$rc)"
        echo "   [DEBUG] Kernel output:"
        echo "$dmesg_after" | sed 's/^/     /'
    fi

    printf " Test %-1s | %-45s | %-8s\n" "$test_id" "$desc" "$result"
done

# Close file descriptor
exec 3>&-

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
