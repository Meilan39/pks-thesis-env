#!/usr/bin/env bash
# ==============================================================================
# test/run.sh - Compliance & Integrity Evaluation Runner
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

EXECUTOR_SCRIPT="$REPO_ROOT/exec/${EXECUTOR:-qemu}.sh"
COMPLIANCE_LEAVES=(fsx pjd pks-unit sanity)
AXIS_CSV="$SCRIPT_DIR/result.csv"

# ------------------------------------------------------------------------------
# 1. Output Initialization
# ------------------------------------------------------------------------------
echo "node,variant,verdict,details" > "$AXIS_CSV"

# ------------------------------------------------------------------------------
# 2. Header Banner
# ------------------------------------------------------------------------------
echo "========================================================================================"
echo " [test] PKS Compliance Evaluation: Kernel Invariants & POSIX Semantics"
echo " Leaves: fsx, pjd, pks-unit, sanity | Modes: off, on | Executor: ${EXECUTOR:-qemu}"
echo "========================================================================================"

pass_count=0
fail_count=0
TABLE_ROWS=()

# ------------------------------------------------------------------------------
# 3. Execution & Evaluation Loop
# ------------------------------------------------------------------------------
# --- Mode: off (Baseline) ---
raw_off="$SCRIPT_DIR/raw-off.log"
"$EXECUTOR_SCRIPT" sec off test "$raw_off" >/dev/null

for leaf in "${COMPLIANCE_LEAVES[@]}"; do
    line_off=$(grep -aoE "STATUS node=${leaf} variant=off .*" "$raw_off" 2>/dev/null | tail -n1)
    verdict_off="FAIL"
    details_off="unresolved"
    if [ -n "$line_off" ]; then
        verdict_off=$(status_field "$line_off" verdict)
        details_off=$(printf '%s\n' "$line_off" | sed -E 's/^STATUS node=[^ ]+ variant=[^ ]+ verdict=[^ ]+ ?//')
        [ -z "$details_off" ] && details_off="ok"
    fi

    color_off="$C_RED"
    if [ "$verdict_off" = "PASS" ]; then
        color_off="$C_GREEN"
        pass_count=$((pass_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi

    echo "$leaf,off,$verdict_off,$details_off" >> "$AXIS_CSV"
    tag_off="[${leaf}-off]"
    printf " %-18s pcache_pks=off ... %b%-4s%b (%s)\n" \
        "$tag_off" "$color_off" "$verdict_off" "$C_RESET" "$details_off"
done

# --- Mode: on (Hardware PKS) ---
raw_on="$SCRIPT_DIR/raw-on.log"
"$EXECUTOR_SCRIPT" sec on test "$raw_on" >/dev/null

for leaf in "${COMPLIANCE_LEAVES[@]}"; do
    line_on=$(grep -aoE "STATUS node=${leaf} variant=on .*" "$raw_on" 2>/dev/null | tail -n1)
    verdict_on="FAIL"
    details_on="unresolved"
    if [ -n "$line_on" ]; then
        verdict_on=$(status_field "$line_on" verdict)
        details_on=$(printf '%s\n' "$line_on" | sed -E 's/^STATUS node=[^ ]+ variant=[^ ]+ verdict=[^ ]+ ?//')
        [ -z "$details_on" ] && details_on="ok"
    fi

    color_on="$C_RED"
    if [ "$verdict_on" = "PASS" ]; then
        color_on="$C_GREEN"
        pass_count=$((pass_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi

    echo "$leaf,on,$verdict_on,$details_on" >> "$AXIS_CSV"
    tag_on="[${leaf}-on]"
    printf " %-18s pcache_pks=on  ... %b%-4s%b (%s)\n" \
        "$tag_on" "$color_on" "$verdict_on" "$C_RESET" "$details_on"
done

# Populate summary table rows
for leaf in "${COMPLIANCE_LEAVES[@]}"; do
    line_off=$(grep -aoE "STATUS node=${leaf} variant=off .*" "$raw_off" 2>/dev/null | tail -n1)
    verdict_off="FAIL"
    details_off="unresolved"
    if [ -n "$line_off" ]; then
        verdict_off=$(status_field "$line_off" verdict)
        details_off=$(printf '%s\n' "$line_off" | sed -E 's/^STATUS node=[^ ]+ variant=[^ ]+ verdict=[^ ]+ ?//')
        [ -z "$details_off" ] && details_off="ok"
    fi
    color_off="$([ "$verdict_off" = "PASS" ] && echo "$C_GREEN" || echo "$C_RED")"

    line_on=$(grep -aoE "STATUS node=${leaf} variant=on .*" "$raw_on" 2>/dev/null | tail -n1)
    verdict_on="FAIL"
    details_on="unresolved"
    if [ -n "$line_on" ]; then
        verdict_on=$(status_field "$line_on" verdict)
        details_on=$(printf '%s\n' "$line_on" | sed -E 's/^STATUS node=[^ ]+ variant=[^ ]+ verdict=[^ ]+ ?//')
        [ -z "$details_on" ] && details_on="ok"
    fi
    color_on="$([ "$verdict_on" = "PASS" ] && echo "$C_GREEN" || echo "$C_RED")"

    TABLE_ROWS+=("$(printf ' %-15s %b%-4s%b %-33s %b%-4s%b %-25s' \
        "$leaf" \
        "$color_off" "$verdict_off" "$C_RESET" "(${details_off})" \
        "$color_on" "$verdict_on" "$C_RESET" "(${details_on})")")
done

# ------------------------------------------------------------------------------
# 4. Summary Table Footer
# ------------------------------------------------------------------------------
overall="PASS"
[ "$fail_count" -gt 0 ] && overall="FAIL"
overall_color="$([ "$overall" = "PASS" ] && echo "$C_GREEN" || echo "$C_RED")"

echo "test,all,$overall,passed=${pass_count}_failed=${fail_count}" >> "$AXIS_CSV"

echo "----------------------------------------------------------------------------------------"
printf " %-15s %-38s %-30s\n" "Test" "pcache_pks=off (Baseline)" "pcache_pks=on (Hardware PKS)"
echo "----------------------------------------------------------------------------------------"
for row in "${TABLE_ROWS[@]}"; do
    echo "$row"
done
echo "----------------------------------------------------------------------------------------"
printf " OVERALL: %b%s%b (%d/8 passing, %d failing)\n" \
    "$overall_color" "$overall" "$C_RESET" "$pass_count" "$fail_count"
echo "========================================================================================"

[ "$overall" = "PASS" ]
