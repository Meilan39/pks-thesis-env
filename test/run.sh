#!/usr/bin/env bash
# ==============================================================================
# test/run.sh - Host Aggregator for Compliance & Integrity Axis
# ==============================================================================
# Boots the diagnostic (sec) kernel once per mode (off, on), runs all four
# compliance leaves (pks-unit, sanity, fsx, pjd) in a single consolidated boot,
# harvests each leaf's STATUS line from the serial transcript, and rolls up.
#
# Because compliance tests are non-destructive and no panics are expected,
# a consolidated boot per mode is safe and significantly faster.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

EXECUTOR_SCRIPT="$REPO_ROOT/exec/${EXECUTOR:-qemu}.sh"
COMPLIANCE_LEAVES=(pks-unit sanity fsx pjd)

# ------------------------------------------------------------------------------
# 1. Clean Environment Initialization
# ------------------------------------------------------------------------------
# Truncate each leaf's result.log and remove stale raw directories from prior runs
for leaf in "${COMPLIANCE_LEAVES[@]}"; do
    : > "$SCRIPT_DIR/$leaf/result.log"
    rm -rf "$SCRIPT_DIR/$leaf/raw"
done

# ------------------------------------------------------------------------------
# 2. Consolidated Execution (One Boot per Mode)
# ------------------------------------------------------------------------------
for mode in off on; do
    transcript_file="$SCRIPT_DIR/raw-${mode}.log"
    
    "$EXECUTOR_SCRIPT" sec "$mode" test "$transcript_file"
    for leaf in "${COMPLIANCE_LEAVES[@]}"; do
        harvest_node "$transcript_file" "$leaf" "$SCRIPT_DIR/$leaf/result.log"
    done
done

# ------------------------------------------------------------------------------
# 3. Validation, Rollup, and CSV Export
# ------------------------------------------------------------------------------
for leaf in "${COMPLIANCE_LEAVES[@]}"; do
    mark_empty_leaves all "$SCRIPT_DIR/$leaf/result.log"
done

rollup "$SCRIPT_DIR/result.log" test "$SCRIPT_DIR"/*/result.log
rollup_rc=$?

statuses_to_csv "$SCRIPT_DIR/result.log" "$REPO_ROOT/results/data/test_summary.csv"
exit "$rollup_rc"
