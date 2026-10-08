#!/usr/bin/env bash
# ==============================================================================
# sec/run.sh - Security Exploit Evaluation Runner
# ==============================================================================
# Runs each exploit leaf (copy-fail, dirty-frag, fragnesia) in its own guest
# boot per mode (off, on), resolves the outcome from the victim-file marker and
# any fail-closed kernel panic, and renders the shared axis console report.
# Structured rows are appended to sec/result.csv.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

EXECUTOR_SCRIPT="$REPO_ROOT/exec/${EXECUTOR:-qemu}.sh"
SECURITY_LEAVES=(copy-fail dirty-frag fragnesia)
AXIS_CSV="$SCRIPT_DIR/result.csv"

# ------------------------------------------------------------------------------
# 1. Output Initialization
# ------------------------------------------------------------------------------
rm -f "$AXIS_CSV" "$SCRIPT_DIR"/*/result.csv
echo "node,variant,verdict,outcome" > "$AXIS_CSV"

# ------------------------------------------------------------------------------
# 2. Header Banner
# ------------------------------------------------------------------------------
report_banner \
    "[sec] PKS Security Evaluation: End-to-End Exploit Neutralization" \
    "Leaves: copy-fail, dirty-frag, fragnesia | Modes: off, on | Executor: ${EXECUTOR:-qemu}"

pass_count=0
fail_count=0
# Per-leaf resolved verdict/outcome for the given mode (reset each leaf).
leaf_verdict_off=""; leaf_outcome_off=""
leaf_verdict_on="";  leaf_outcome_on=""

# Resolves the marker outcome for one leaf/mode, tallies counters, prints the
# live line, records the CSV row, and stashes the result for the summary table.
# The 'off' baseline passes when the marker was altered (a real vulnerability);
# 'on' passes when the marker survived or a PKS-attributable panic trapped the store.
resolve_leaf() {
    local leaf="$1"
    local variant="$2"
    local raw_log="$3"

    local marker outcome verdict
    marker=$(grep -aoE 'marker=(intact|altered)' "$raw_log" 2>/dev/null | tail -n1 | cut -d= -f2)

    if [ "$variant" = "on" ] \
        && grep -qE "$PKS_PANIC_REGEX" "$raw_log" 2>/dev/null \
        && grep -qE "$PKS_ACTIVE_REGEX" "$raw_log" 2>/dev/null; then
        outcome="fail_closed_panic"
    else
        outcome="${marker:-unresolved}"
    fi

    verdict="FAIL"
    if [ "$variant" = "off" ]; then
        [ "$outcome" = "altered" ] && verdict="PASS"
    else
        { [ "$outcome" = "intact" ] || [ "$outcome" = "fail_closed_panic" ]; } && verdict="PASS"
    fi

    if [ "$variant" = "off" ]; then
        leaf_verdict_off="$verdict"; leaf_outcome_off="$outcome"
    else
        leaf_verdict_on="$verdict";  leaf_outcome_on="$outcome"
    fi

    if [ "$verdict" = "PASS" ]; then
        pass_count=$((pass_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi

    echo "$leaf,$variant,$verdict,$outcome" >> "$AXIS_CSV"
    report_leaf "[${leaf}-${variant}]" "pcache_pks=${variant}" "$verdict" "outcome=$outcome"
}

# ------------------------------------------------------------------------------
# 3. Execution & Evaluation Loop
# ------------------------------------------------------------------------------
TABLE_ROWS=()
for leaf in "${SECURITY_LEAVES[@]}"; do
    leaf_dir="$SCRIPT_DIR/$leaf"
    for variant in off on; do
        raw_log="$leaf_dir/raw-${variant}.log"
        "$EXECUTOR_SCRIPT" sec "$variant" "sec/$leaf" "$raw_log" >/dev/null
        resolve_leaf "$leaf" "$variant" "$raw_log"
    done
    TABLE_ROWS+=("$(report_compare_row "$leaf" \
        "$leaf_verdict_off" "$leaf_outcome_off" \
        "$leaf_verdict_on"  "$leaf_outcome_on")")
done

# ------------------------------------------------------------------------------
# 4. Summary Table Footer
# ------------------------------------------------------------------------------
overall="PASS"
[ "$fail_count" -gt 0 ] && overall="FAIL"

echo "sec,all,$overall,passed=${pass_count}_failed=${fail_count}" >> "$AXIS_CSV"

report_compare_head "Exploit" "pcache_pks=off (Baseline)" "pcache_pks=on (Hardware PKS)"
for row in "${TABLE_ROWS[@]}"; do
    printf '%s\n' "$row"
done
report_hrule
report_overall "$overall" "$pass_count/6 passing, $fail_count failing"
report_rule

[ "$overall" = "PASS" ]
