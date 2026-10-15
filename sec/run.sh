#!/usr/bin/env bash
# ==============================================================================
# sec/run.sh - Security Exploit Evaluation Runner
# ==============================================================================
# Evaluates exploit leaves (copy-fail, dirty-frag, fragnesia) under off and on.
# Under off, an altered marker confirms vulnerability (PASS); intact is a FAIL.
# Under on, an intact marker confirms in-place neutralization (PASS); panic/altered is FAIL.
# Structured rows are written to sec/result.csv.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

EXECUTOR="${EXECUTOR:-qemu}"
EXECUTOR_SCRIPT="$REPO_ROOT/exec/${EXECUTOR}.sh"
SECURITY_LEAVES=(copy-fail dirty-frag fragnesia)
AXIS_CSV="$SCRIPT_DIR/result.csv"

# ------------------------------------------------------------------------------
# Reset axis CSV
# ------------------------------------------------------------------------------
rm -f "$AXIS_CSV" "$SCRIPT_DIR"/*/result.csv
echo "node,variant,verdict,outcome" > "$AXIS_CSV"

# ------------------------------------------------------------------------------
# Console banner
# ------------------------------------------------------------------------------
report_banner \
    "[sec] PKS Security Evaluation: End-to-End Exploit Neutralization" \
    "Leaves: copy-fail, dirty-frag, fragnesia | Modes: off, on | Executor: $EXECUTOR"

# ------------------------------------------------------------------------------
# Boot each leaf per mode, evaluate outcomes and verdicts
# ------------------------------------------------------------------------------
pass_count=0
fail_count=0
TABLE_ROWS=()

for leaf in "${SECURITY_LEAVES[@]}"; do
    leaf_dir="$SCRIPT_DIR/$leaf"
    for variant in off on; do
        raw_log="$leaf_dir/raw-${variant}.log"
        "$EXECUTOR_SCRIPT" sec "$variant" "sec/$leaf" "$raw_log" >/dev/null

        # Panic check: unhandled oops or panic is recorded as fail_closed_panic
        if grep -qE "$PKS_PANIC_REGEX" "$raw_log" 2>/dev/null; then
            outcome="fail_closed_panic"
        else
            marker=$(grep -aoE 'marker=(intact|altered)' "$raw_log" 2>/dev/null | tail -n1 | cut -d= -f2)
            outcome="${marker:-unresolved}"
        fi

        # off passes iff altered (exploit works); on passes iff intact (isolated in place)
        if [ "$variant" = "off" ] && [ "$outcome" = "altered" ]; then
            verdict="PASS"
        elif [ "$variant" = "on" ] && [ "$outcome" = "intact" ]; then
            verdict="PASS"
        else
            verdict="FAIL"
        fi

        if [ "$verdict" = "PASS" ]; then
            pass_count=$((pass_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi

        echo "$leaf,$variant,$verdict,$outcome" >> "$AXIS_CSV"
        report_leaf "[${leaf}-${variant}]" "pcache_pks=${variant}" "$verdict" "outcome=$outcome"

        if [ "$variant" = "off" ]; then
            v_off="$verdict"; out_off="$outcome"
        else
            v_on="$verdict";  out_on="$outcome"
        fi
    done

    TABLE_ROWS+=("$(report_compare_row "$leaf" "$v_off" "$out_off" "$v_on" "$out_on")")
done

# ------------------------------------------------------------------------------
# Summary footer
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
