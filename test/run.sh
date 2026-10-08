#!/usr/bin/env bash
# ==============================================================================
# test/run.sh - Compliance & Integrity Evaluation Runner
# ==============================================================================
# Boots the guest once per mode (off, on), harvests the three compliance leaves
# (fsx, pks-unit, sanity) from each serial transcript, and renders the
# shared axis console report. Structured rows are appended to test/result.csv.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

EXECUTOR_SCRIPT="$REPO_ROOT/exec/${EXECUTOR:-qemu}.sh"
COMPLIANCE_LEAVES=(fsx pks-unit sanity)
AXIS_CSV="$SCRIPT_DIR/result.csv"

# ------------------------------------------------------------------------------
# 1. Output Initialization
# ------------------------------------------------------------------------------
echo "node,variant,verdict,details" > "$AXIS_CSV"

# ------------------------------------------------------------------------------
# 2. Header Banner
# ------------------------------------------------------------------------------
report_banner \
    "[test] PKS Compliance Evaluation: Kernel Invariants & POSIX Semantics" \
    "Leaves: fsx, pks-unit, sanity | Modes: off, on | Executor: ${EXECUTOR:-qemu}"

pass_count=0
fail_count=0
# Per-leaf verdict/detail, indexed in lockstep with COMPLIANCE_LEAVES.
V_OFF=(); D_OFF=()
V_ON=();  D_ON=()

# Harvests one leaf verdict/detail from a transcript into the per-mode arrays at
# the given index, tallies the global counters, prints its live line, and records
# the CSV row.
harvest_leaf() {
    local raw_log="$1"
    local leaf="$2"
    local variant="$3"
    local idx="$4"

    local line verdict details
    line=$(grep -aoE "STATUS node=${leaf} variant=${variant} .*" "$raw_log" 2>/dev/null | tail -n1)
    verdict="FAIL"
    details="unresolved"
    if [ -n "$line" ]; then
        verdict=$(status_field "$line" verdict)
        details=$(status_detail_tail "$line")
        [ -z "$details" ] && details="ok"
    fi

    if [ "$variant" = "off" ]; then
        V_OFF[$idx]="$verdict"; D_OFF[$idx]="$details"
    else
        V_ON[$idx]="$verdict";  D_ON[$idx]="$details"
    fi

    if [ "$verdict" = "PASS" ]; then
        pass_count=$((pass_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi

    echo "$leaf,$variant,$verdict,$details" >> "$AXIS_CSV"
    report_leaf "[${leaf}-${variant}]" "pcache_pks=${variant}" "$verdict" "$details"
}

# ------------------------------------------------------------------------------
# 3. Execution & Evaluation Loop
# ------------------------------------------------------------------------------
for variant in off on; do
    raw_log="$SCRIPT_DIR/raw-${variant}.log"
    "$EXECUTOR_SCRIPT" sec "$variant" test "$raw_log" >/dev/null
    idx=0
    for leaf in "${COMPLIANCE_LEAVES[@]}"; do
        harvest_leaf "$raw_log" "$leaf" "$variant" "$idx"
        idx=$((idx + 1))
    done
done

# ------------------------------------------------------------------------------
# 4. Summary Table Footer
# ------------------------------------------------------------------------------
overall="PASS"
[ "$fail_count" -gt 0 ] && overall="FAIL"

echo "test,all,$overall,passed=${pass_count}_failed=${fail_count}" >> "$AXIS_CSV"

report_compare_head "Test" "pcache_pks=off (Baseline)" "pcache_pks=on (Hardware PKS)"
idx=0
for leaf in "${COMPLIANCE_LEAVES[@]}"; do
    report_compare_row "$leaf" \
        "${V_OFF[$idx]}" "${D_OFF[$idx]}" \
        "${V_ON[$idx]}"  "${D_ON[$idx]}"
    idx=$((idx + 1))
done
report_hrule
report_overall "$overall" "$pass_count/6 passing, $fail_count failing"
report_rule

[ "$overall" = "PASS" ]
