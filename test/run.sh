#!/usr/bin/env bash
# ==============================================================================
# test/run.sh - Compliance axis aggregator
# ==============================================================================
# Boots the guest once per mode (off, on), harvests the three leaves (fsx,
# pks-unit, sanity) from each serial transcript, renders the console report, and
# appends rows to test/result.csv.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

EXECUTOR="${EXECUTOR:-qemu}"
EXECUTOR_SCRIPT="$REPO_ROOT/exec/${EXECUTOR}.sh"
COMPLIANCE_LEAVES=(fsx pks-unit sanity)
AXIS_CSV="$SCRIPT_DIR/result.csv"

# ------------------------------------------------------------------------------
# Reset axis CSV
# ------------------------------------------------------------------------------
echo "node,variant,verdict,details" > "$AXIS_CSV"

# ------------------------------------------------------------------------------
# Console banner
# ------------------------------------------------------------------------------
report_banner \
    "[test] PKS Compliance Evaluation: Kernel Invariants & POSIX Semantics" \
    "Leaves: fsx, pks-unit, sanity | Modes: off, on | Executor: $EXECUTOR"

# Renders a leaf's streamed check lines as an indented per-check report. Leaves
# stream raw [PASS]/[FAIL]/[SKIP] (sanity) or [RUN]+[OK]/[FAIL] (pks-unit); we
# buffer the lines before each STATUS node=<leaf> and flush them at that
# boundary, stripping the "[ts] pks-autorun.sh[pid]:" journal prefix.
emit_leaf_checks() {
    local raw_log="$1"
    local leaf="$2"

    local verdict desc
    while IFS=$'\t' read -r verdict desc; do
        [ -n "$verdict" ] && report_check "$desc" "$verdict"
    done < <(awk -v leaf="$leaf" '
        function strip(s){ sub(/^\[[^]]*\][ ]+[^:]*:[ ]+/, "", s); gsub(/\r/, "", s); return s }
        {
            l = strip($0)
            if (l ~ /^STATUS node=/) {
                n = l; sub(/^STATUS node=/, "", n); sub(/[ ].*/, "", n)
                if (n == leaf) for (i = 0; i < nb; i++) print buf[i]
                nb = 0; pend = ""; next
            }
            if (l ~ /\[RUN\]/)  { pend = l; sub(/.*\[RUN\][ \t]*/, "", pend); next }
            if (l ~ /\[OK\]/)   { buf[nb++] = "PASS\t" (pend != "" ? pend : "pks test"); pend = ""; next }
            if (l ~ /\[PASS\]/) { d = l; sub(/.*\[PASS\][ \t]*/, "", d); buf[nb++] = "PASS\t" d; next }
            if (l ~ /\[FAIL\]/) { d = l; sub(/.*\[FAIL\][ \t]*/, "", d)
                                  buf[nb++] = "FAIL\t" (pend != "" ? pend : d); pend = ""; next }
            if (l ~ /\[SKIP\]/) { d = l; sub(/.*\[SKIP\][ \t]*/, "", d)
                                  buf[nb++] = "SKIP\t" (pend != "" ? pend : d); pend = ""; next }
        }
    ' "$raw_log" 2>/dev/null)
}

# ------------------------------------------------------------------------------
# Boot each mode, harvest leaves
# ------------------------------------------------------------------------------
for variant in off on; do
    raw_log="$SCRIPT_DIR/raw-${variant}.log"
    "$EXECUTOR_SCRIPT" sec "$variant" test "$raw_log" >/dev/null

    for leaf in "${COMPLIANCE_LEAVES[@]}"; do
        # Panic check: unhandled oops or panic is recorded as fail
        if grep -qE "$PKS_PANIC_REGEX" "$raw_log" 2>/dev/null; then
            verdict="FAIL"
            details="kernel_panic"
        else
            line=$(grep -aoE "STATUS node=${leaf} variant=${variant} .*" "$raw_log" 2>/dev/null | tail -n1)
            verdict="FAIL"
            details="unresolved"
            if [ -n "$line" ]; then
                verdict=$(status_field "$line" verdict)
                details=$(status_detail_tail "$line")
                [ -z "$details" ] && details="ok"
            fi
        fi

        echo "$leaf,$variant,$verdict,$details" >> "$AXIS_CSV"
        report_leaf "[${leaf}-${variant}]" "pcache_pks=${variant}" "$verdict" "$details"
        emit_leaf_checks "$raw_log" "$leaf"
    done
done

# ------------------------------------------------------------------------------
# Summary footer
# ------------------------------------------------------------------------------
leaves_total=${#COMPLIANCE_LEAVES[@]}
leaves_passed=0
TABLE_ROWS=()

for leaf in "${COMPLIANCE_LEAVES[@]}"; do
    row_off=$(grep -aoE "^${leaf},off,.*" "$AXIS_CSV" 2>/dev/null | tail -n1)
    row_on=$(grep -aoE "^${leaf},on,.*" "$AXIS_CSV" 2>/dev/null | tail -n1)

    v_off=$(printf '%s\n' "$row_off" | cut -d, -f3)
    d_off=$(printf '%s\n' "$row_off" | cut -d, -f4-)
    v_on=$(printf '%s\n' "$row_on" | cut -d, -f3)
    d_on=$(printf '%s\n' "$row_on" | cut -d, -f4-)

    if [ "$v_off" = "PASS" ] && [ "$v_on" = "PASS" ]; then
        leaves_passed=$((leaves_passed + 1))
    fi

    TABLE_ROWS+=("$(report_compare_row "$leaf" "${v_off:-FAIL}" "${d_off:-unresolved}" "${v_on:-FAIL}" "${d_on:-unresolved}")")
done

leaves_failed=$((leaves_total - leaves_passed))
overall="PASS"
[ "$leaves_failed" -gt 0 ] && overall="FAIL"

echo "test,all,$overall,passed=${leaves_passed}_failed=${leaves_failed}_of=${leaves_total}" >> "$AXIS_CSV"

report_compare_head "Test" "pcache_pks=off (Baseline)" "pcache_pks=on (Hardware PKS)"
for row in "${TABLE_ROWS[@]}"; do
    printf '%s\n' "$row"
done
report_hrule
report_overall "$overall" "${leaves_passed}/${leaves_total} leaves passing, ${leaves_failed} failing"
report_rule

[ "$overall" = "PASS" ]
