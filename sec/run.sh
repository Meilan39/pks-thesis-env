#!/usr/bin/env bash
# ==============================================================================
# sec/run.sh - Security Exploit Evaluation Runner
# ==============================================================================
# Evaluates exploit leaves (copy-fail, dirty-frag, fragnesia) under off and on.
# Under off, an altered marker confirms vulnerability (PASS); intact is a FAIL.
# Under on, an intact marker confirms in-place neutralization (PASS); a panic or
# an altered marker is a FAIL.
#
# One guest boot per mode runs ALL three leaves in sequence (the stateless fault
# handler neutralizes every vector in place without panicking, so the former
# per-leaf isolation boot is unnecessary -- and on bare metal it collapses six
# reboots into two). Each leaf's marker is harvested from the shared transcript
# using the "### PKS-LEAF <leaf>" delimiters the dispatcher emits.
# Structured rows are written to sec/result.csv.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

EXECUTOR="$(resolve_executor "${EXECUTOR:-auto}")"
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

# Extract one leaf's marker from a batched transcript: isolate the segment that
# follows "### PKS-LEAF <leaf>" (up to the next leaf delimiter) and read its last
# marker= line. CR is stripped because serial transcripts are CRLF.
extract_marker() {
    local raw_log="$1"
    local leaf="$2"
    awk -v leaf="$leaf" '
        { gsub(/\r/, "") }
        index($0, "### PKS-LEAF " leaf) { cap = 1; next }
        cap == 1 && index($0, "### PKS-LEAF ") { exit }
        cap == 1 { print }
    ' "$raw_log" 2>/dev/null \
        | grep -aoE 'marker=(intact|altered)' | tail -n1 | cut -d= -f2
}

# Per-leaf resolved verdict/outcome, indexed in lockstep with SECURITY_LEAVES.
V_OFF=(); O_OFF=()
V_ON=();  O_ON=()

pass_count=0
fail_count=0

# ------------------------------------------------------------------------------
# Boot each mode once; all three leaves run in that single boot.
# ------------------------------------------------------------------------------
for variant in off on; do
    raw_log="$SCRIPT_DIR/raw-${variant}.log"
    "$EXECUTOR_SCRIPT" sec "$variant" sec "$raw_log" >/dev/null

    # A panic (or unhandled oops) halts the boot: every leaf in it is suspect.
    # With the stateless handler this must not happen under 'on'; if it does it
    # is a real regression, so it fails closed below.
    panicked=0
    grep -qE "$PKS_PANIC_REGEX" "$raw_log" 2>/dev/null && panicked=1

    idx=0
    for leaf in "${SECURITY_LEAVES[@]}"; do
        if [ "$panicked" -eq 1 ]; then
            outcome="fail_closed_panic"
        else
            marker="$(extract_marker "$raw_log" "$leaf")"
            outcome="${marker:-unresolved}"
        fi

        # off passes iff altered (exploit works); on passes iff intact (trapped).
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

        if [ "$variant" = "off" ]; then
            V_OFF[$idx]="$verdict"; O_OFF[$idx]="$outcome"
        else
            V_ON[$idx]="$verdict";  O_ON[$idx]="$outcome"
        fi

        echo "$leaf,$variant,$verdict,$outcome" >> "$AXIS_CSV"
        report_leaf "[${leaf}-${variant}]" "pcache_pks=${variant}" "$verdict" "outcome=$outcome"
        idx=$((idx + 1))
    done
done

# ------------------------------------------------------------------------------
# Summary footer
# ------------------------------------------------------------------------------
overall="PASS"
[ "$fail_count" -gt 0 ] && overall="FAIL"

echo "sec,all,$overall,passed=${pass_count}_failed=${fail_count}" >> "$AXIS_CSV"

report_compare_head "Exploit" "pcache_pks=off (Baseline)" "pcache_pks=on (Hardware PKS)"
idx=0
for leaf in "${SECURITY_LEAVES[@]}"; do
    report_compare_row "$leaf" \
        "${V_OFF[$idx]}" "${O_OFF[$idx]}" \
        "${V_ON[$idx]}"  "${O_ON[$idx]}"
    idx=$((idx + 1))
done
report_hrule
report_overall "$overall" "$pass_count/6 passing, $fail_count failing"
report_rule

[ "$overall" = "PASS" ]
