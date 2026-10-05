#!/usr/bin/env bash
# ==============================================================================
# sec/run.sh - Security Exploit Evaluation Runner
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

EXECUTOR_SCRIPT="$REPO_ROOT/exec/${EXECUTOR:-qemu}.sh"
SECURITY_LEAVES=(copy-fail dirty-frag fragnesia)
AXIS_CSV="$SCRIPT_DIR/result.csv"

# ------------------------------------------------------------------------------
# 1. Clean Initialization
# ------------------------------------------------------------------------------
rm -f "$AXIS_CSV" "$SCRIPT_DIR"/*/result.csv
echo "node,variant,verdict,outcome" > "$AXIS_CSV"

# ------------------------------------------------------------------------------
# 2. Header Banner
# ------------------------------------------------------------------------------
echo "========================================================================================"
echo " [sec] PKS Security Evaluation: End-to-End Exploit Neutralization"
echo " Leaves: copy-fail, dirty-frag, fragnesia | Modes: off, on | Executor: ${EXECUTOR:-qemu}"
echo "========================================================================================"

pass_count=0
fail_count=0
TABLE_ROWS=()

# ------------------------------------------------------------------------------
# 3. Execution & Evaluation Loop
# ------------------------------------------------------------------------------
for leaf in "${SECURITY_LEAVES[@]}"; do
    leaf_dir="$SCRIPT_DIR/$leaf"

    # --- Mode: off (Baseline) ---
    raw_off="$leaf_dir/raw-off.log"
    "$EXECUTOR_SCRIPT" sec off "sec/$leaf" "$raw_off" >/dev/null

    marker_off=$(grep -aoE 'marker=(intact|altered)' "$raw_off" 2>/dev/null | tail -n1 | cut -d= -f2)
    outcome_off="${marker_off:-unresolved}"

    verdict_off="FAIL"
    [ "$outcome_off" = "altered" ] && verdict_off="PASS"

    color_off="$C_RED"
    if [ "$verdict_off" = "PASS" ]; then
        color_off="$C_GREEN"
        pass_count=$((pass_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi

    echo "$leaf,off,$verdict_off,$outcome_off" >> "$AXIS_CSV"
    tag_off="[${leaf}-off]"
    printf " %-18s pcache_pks=off ... %b%-4s%b (outcome=%s)\n" \
        "$tag_off" "$color_off" "$verdict_off" "$C_RESET" "$outcome_off"

    # --- Mode: on (Mitigated) ---
    raw_on="$leaf_dir/raw-on.log"
    "$EXECUTOR_SCRIPT" sec on "sec/$leaf" "$raw_on" >/dev/null

    marker_on=$(grep -aoE 'marker=(intact|altered)' "$raw_on" 2>/dev/null | tail -n1 | cut -d= -f2)
    if grep -qE "$PKS_PANIC_REGEX" "$raw_on" 2>/dev/null && grep -qE "$PKS_ACTIVE_REGEX" "$raw_on" 2>/dev/null; then
        outcome_on="fail_closed_panic"
    elif [ -n "$marker_on" ]; then
        outcome_on="$marker_on"
    else
        outcome_on="unresolved"
    fi

    verdict_on="FAIL"
    if [ "$outcome_on" = "intact" ] || [ "$outcome_on" = "fail_closed_panic" ]; then
        verdict_on="PASS"
    fi

    color_on="$C_RED"
    if [ "$verdict_on" = "PASS" ]; then
        color_on="$C_GREEN"
        pass_count=$((pass_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi

    echo "$leaf,on,$verdict_on,$outcome_on" >> "$AXIS_CSV"
    tag_on="[${leaf}-on]"
    printf " %-18s pcache_pks=on  ... %b%-4s%b (outcome=%s)\n" \
        "$tag_on" "$color_on" "$verdict_on" "$C_RESET" "$outcome_on"

    # Insert variables directly into summary table row template
    TABLE_ROWS+=("$(printf ' %-15s %b%-4s%b %-33s %b%-4s%b %-25s' \
        "$leaf" \
        "$color_off" "$verdict_off" "$C_RESET" "(${outcome_off})" \
        "$color_on" "$verdict_on" "$C_RESET" "(${outcome_on})")")
done

# ------------------------------------------------------------------------------
# 4. Summary Table Footer
# ------------------------------------------------------------------------------
overall="PASS"
[ "$fail_count" -gt 0 ] && overall="FAIL"
overall_color="$([ "$overall" = "PASS" ] && echo "$C_GREEN" || echo "$C_RED")"

echo "sec,all,$overall,passed=${pass_count}_failed=${fail_count}" >> "$AXIS_CSV"

echo "----------------------------------------------------------------------------------------"
printf " %-15s %-38s %-30s\n" "Exploit" "pcache_pks=off (Baseline)" "pcache_pks=on (Hardware PKS)"
echo "----------------------------------------------------------------------------------------"
for row in "${TABLE_ROWS[@]}"; do
    echo "$row"
done
echo "----------------------------------------------------------------------------------------"
printf " OVERALL: %b%s%b (%d/6 passing, %d failing)\n" \
    "$overall_color" "$overall" "$C_RESET" "$pass_count" "$fail_count"
echo "========================================================================================"

[ "$overall" = "PASS" ]


