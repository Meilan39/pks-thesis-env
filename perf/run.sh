#!/usr/bin/env bash
# ==============================================================================
# perf/run.sh - Performance & Overhead Evaluation Runner
# ==============================================================================
# Executes consolidated evaluation runs across experimental variants:
#   - control: baseline kernel, unmitigated
#   - off: mitigated kernel with PKS disabled (ablation baseline)
#   - on: mitigated kernel with PKS enabled (hardware write isolation)
#
# Emits live execution stream and dual summary tables:
#   Table 1: Fio Latency & Allocation Cost Breakdown
#   Table 2: High-Level Performance Comparison (control, off, on, overhead)
#
# Data persistence: perf/result.csv and results/data/perf_summary.csv
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

EXECUTOR_SCRIPT="$REPO_ROOT/exec/${EXECUTOR:-qemu}.sh"
PERF_LEAVES=(fio concurrency sqlite)
AXIS_CSV="$SCRIPT_DIR/result.csv"

# ------------------------------------------------------------------------------
# Reset axis CSV
# ------------------------------------------------------------------------------
echo "node,variant,verdict,details" > "$AXIS_CSV"

# ------------------------------------------------------------------------------
# Console banner
# ------------------------------------------------------------------------------
report_banner \
    "[perf] PKS Performance Evaluation: Micro- & Macrobenchmarks" \
    "Workloads: fio (warm/cold), concurrency, sqlite | Variants: control, off, on"

calc_overhead() {
    local base="$1"
    local curr="$2"
    python3 -c "
try:
    b = float('$base')
    c = float('$curr')
    if b == 0:
        print('N/A')
    else:
        ovh = ((c / b) - 1.0) * 100.0
        print(f'{ovh:+.2f}%')
except Exception:
    print('N/A')
" 2>/dev/null || echo "N/A"
}

# ------------------------------------------------------------------------------
# Run each variant, harvest leaves
# ------------------------------------------------------------------------------
pass_count=0
fail_count=0

run_and_harvest() {
    local variant="$1"
    local kernel_variant="$2"
    local pks_mode="$3"
    local raw_log="$SCRIPT_DIR/raw-${variant}.log"

    "$EXECUTOR_SCRIPT" "$kernel_variant" "$pks_mode" perf "$raw_log" >/dev/null

    for leaf in "${PERF_LEAVES[@]}"; do
        line=$(grep -aoE "STATUS node=${leaf} variant=${variant} .*" "$raw_log" 2>/dev/null | tail -n1)
        verdict="FAIL"
        details="unresolved"
        if [ -n "$line" ]; then
            verdict=$(status_field "$line" verdict)
            details=$(status_detail_tail "$line")
            [ -z "$details" ] && details="ok"
        fi

        if [ "$verdict" = "PASS" ]; then
            pass_count=$((pass_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi

        echo "$leaf,$variant,$verdict,$details" >> "$AXIS_CSV"
        report_leaf "[${leaf}-${variant}]" "$variant" "$verdict" "$details"
    done
}

run_and_harvest control control off
run_and_harvest off     perf    off
run_and_harvest on      perf    on

# ------------------------------------------------------------------------------
# Summary tables & analysis
# ------------------------------------------------------------------------------
echo ""
report_rule
echo " Table 1: Fio Latency & Allocation Cost Breakdown"
report_hrule
printf " %-12s %-16s %-16s %-18s %-12s %-12s\n" \
    "Variant" "4K Warm (us)" "4K Cold (us)" "Alloc Delta (us)" "4K IOPS" "1M Read (MB/s)"
report_hrule

for v in control off on; do
    fio_line=$(grep -aoE "^fio,${v},.*" "$AXIS_CSV" 2>/dev/null | tail -n1)
    f_warm=$(printf '%s\n' "$fio_line" | tr ', ' '\n\n' | sed -n 's/^lat4k_warm_write_us=//p' | head -n1)
    f_cold=$(printf '%s\n' "$fio_line" | tr ', ' '\n\n' | sed -n 's/^lat4k_cold_write_us=//p' | head -n1)
    f_delta=$(printf '%s\n' "$fio_line" | tr ', ' '\n\n' | sed -n 's/^alloc_overhead_us=//p' | head -n1)
    f_iops=$(printf '%s\n' "$fio_line" | tr ', ' '\n\n' | sed -n 's/^iops4k_warm_write=//p' | head -n1)
    f_bw_kib=$(printf '%s\n' "$fio_line" | tr ', ' '\n\n' | sed -n 's/^bw1m_seq_read_kbs=//p' | head -n1)

    f_read_mb=$(python3 -c "
try:
    print(round(float('$f_bw_kib') / 1024.0, 1))
except Exception:
    print('N/A')
" 2>/dev/null || echo "N/A")

    printf " %-12s %-16s %-16s %-18s %-12s %-12s\n" \
        "$v" "${f_warm:-N/A}" "${f_cold:-N/A}" "${f_delta:-N/A}" "${f_iops:-N/A}" "${f_read_mb:-N/A}"
done
report_hrule

echo ""
report_rule
echo " Table 2: High-Level Performance Comparison"
report_hrule
printf " %-16s %-20s %-12s %-12s %-12s %-16s\n" \
    "Benchmark" "Metric" "Control" "Off" "On" "PKS Overhead (%)"
report_hrule

get_detail() {
    local node="$1"
    local var="$2"
    local field="$3"
    local l
    l=$(grep -aoE "^${node},${var},.*" "$AXIS_CSV" 2>/dev/null | tail -n1)
    printf '%s\n' "$l" | tr ', ' '\n\n' | sed -n "s/^${field}=//p" | head -n1
}

# fio warm write lat
f_w_c=$(get_detail fio control lat4k_warm_write_us)
f_w_off=$(get_detail fio off lat4k_warm_write_us)
f_w_on=$(get_detail fio on lat4k_warm_write_us)
f_w_ovh=$(calc_overhead "$f_w_c" "$f_w_on")
printf " %-16s %-20s %-12s %-12s %-12s %-16s\n" \
    "fio 4KB warm" "Write Lat (us)" "${f_w_c:-N/A}" "${f_w_off:-N/A}" "${f_w_on:-N/A}" "$f_w_ovh"

# fio warm read lat
f_r_c=$(get_detail fio control lat4k_warm_read_us)
f_r_off=$(get_detail fio off lat4k_warm_read_us)
f_r_on=$(get_detail fio on lat4k_warm_read_us)
f_r_ovh=$(calc_overhead "$f_r_c" "$f_r_on")
printf " %-16s %-20s %-12s %-12s %-12s %-16s\n" \
    "fio 4KB warm" "Read Lat (us)" "${f_r_c:-N/A}" "${f_r_off:-N/A}" "${f_r_on:-N/A}" "$f_r_ovh"

# fio cold write lat
f_c_c=$(get_detail fio control lat4k_cold_write_us)
f_c_off=$(get_detail fio off lat4k_cold_write_us)
f_c_on=$(get_detail fio on lat4k_cold_write_us)
f_c_ovh=$(calc_overhead "$f_c_c" "$f_c_on")
printf " %-16s %-20s %-12s %-12s %-12s %-16s\n" \
    "fio 4KB cold" "Write Lat (us)" "${f_c_c:-N/A}" "${f_c_off:-N/A}" "${f_c_on:-N/A}" "$f_c_ovh"

# concurrency 4-thread bw
c_4_c=$(get_detail concurrency control bw_4t_mbps)
c_4_off=$(get_detail concurrency off bw_4t_mbps)
c_4_on=$(get_detail concurrency on bw_4t_mbps)
c_4_ovh=$(calc_overhead "$c_4_c" "$c_4_on")
printf " %-16s %-20s %-12s %-12s %-12s %-16s\n" \
    "concurrency" "4-Thread BW (MB/s)" "${c_4_c:-N/A}" "${c_4_off:-N/A}" "${c_4_on:-N/A}" "$c_4_ovh"

# sqlite sync=OFF
s_off_c=$(get_detail sqlite control tps_syncoff)
s_off_off=$(get_detail sqlite off tps_syncoff)
s_off_on=$(get_detail sqlite on tps_syncoff)
s_off_ovh=$(calc_overhead "$s_off_c" "$s_off_on")
printf " %-16s %-20s %-12s %-12s %-12s %-16s\n" \
    "sqlite" "Tx/s (sync=OFF)" "${s_off_c:-N/A}" "${s_off_off:-N/A}" "${s_off_on:-N/A}" "$s_off_ovh"

# sqlite sync=FULL
s_full_c=$(get_detail sqlite control tps_syncfull)
s_full_off=$(get_detail sqlite off tps_syncfull)
s_full_on=$(get_detail sqlite on tps_syncfull)
s_full_ovh=$(calc_overhead "$s_full_c" "$s_full_on")
printf " %-16s %-20s %-12s %-12s %-12s %-16s\n" \
    "sqlite" "Tx/s (sync=FULL)" "${s_full_c:-N/A}" "${s_full_off:-N/A}" "${s_full_on:-N/A}" "$s_full_ovh"

report_hrule

overall="PASS"
[ "$fail_count" -gt 0 ] && overall="FAIL"

echo "perf,all,$overall,completed=${pass_count}_failed=${fail_count}" >> "$AXIS_CSV"

report_overall "$overall" "$pass_count/9 benchmark runs completed, $fail_count failing"
report_rule

python3 "$SCRIPT_DIR/analyze.py" "$SCRIPT_DIR" "$REPO_ROOT/results/data/perf_summary.csv" >/dev/null 2>&1 || true

[ "$overall" = "PASS" ]

