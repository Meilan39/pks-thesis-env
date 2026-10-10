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

EXECUTOR_SCRIPT="$REPO_ROOT/exec/${EXECUTOR:-qemu}.sh"
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
    "Leaves: fsx, pks-unit, sanity | Modes: off, on | Executor: ${EXECUTOR:-qemu}"

# Per-leaf verdict/detail, indexed in lockstep with COMPLIANCE_LEAVES.
V_OFF=(); D_OFF=()
V_ON=();  D_ON=()

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
        function strip(s){ sub(/^\[[^]]*\][ ]+[^:]*:[ ]+/, "", s); return s }
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

# Harvests one leaf's verdict/detail from the transcript into the per-mode
# arrays, writes its CSV row, prints its live line, and renders its checks.
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

    echo "$leaf,$variant,$verdict,$details" >> "$AXIS_CSV"
    report_leaf "[${leaf}-${variant}]" "pcache_pks=${variant}" "$verdict" "$details"
    emit_leaf_checks "$raw_log" "$leaf"
}

# ------------------------------------------------------------------------------
# Boot each mode, harvest its leaves
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
# Summary footer
# ------------------------------------------------------------------------------
# Count at the leaf level, not per leaf-variant: each leaf is one test and passes
# only if it holds under both off and on (e.g. "2/3 leaves passing").
leaves_total=${#COMPLIANCE_LEAVES[@]}
leaves_passed=0
idx=0
for leaf in "${COMPLIANCE_LEAVES[@]}"; do
    if verdict_is_pass "${V_OFF[$idx]}" off && verdict_is_pass "${V_ON[$idx]}" on; then
        leaves_passed=$((leaves_passed + 1))
    fi
    idx=$((idx + 1))
done
leaves_failed=$((leaves_total - leaves_passed))

overall="PASS"
[ "$leaves_failed" -gt 0 ] && overall="FAIL"

echo "test,all,$overall,passed=${leaves_passed}_failed=${leaves_failed}_of=${leaves_total}" >> "$AXIS_CSV"

report_compare_head "Test" "pcache_pks=off (Baseline)" "pcache_pks=on (Hardware PKS)"
idx=0
for leaf in "${COMPLIANCE_LEAVES[@]}"; do
    report_compare_row "$leaf" \
        "${V_OFF[$idx]}" "${D_OFF[$idx]}" \
        "${V_ON[$idx]}"  "${D_ON[$idx]}"
    idx=$((idx + 1))
done
report_hrule
report_overall "$overall" "${leaves_passed}/${leaves_total} leaves passing, ${leaves_failed} failing"
report_rule

[ "$overall" = "PASS" ]
