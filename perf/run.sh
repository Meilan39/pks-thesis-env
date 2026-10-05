#!/usr/bin/env bash
# perf/run.sh - HOST aggregator for the performance axis.
# Executes one consolidated boot per experimental variant:
#   - control: baseline kernel, unmitigated
#   - off: mitigated kernel with PKS disabled (ablation baseline)
#   - on: mitigated kernel with PKS enabled
# Leaves emit quantitative metrics parsed from fio and sqlite benchmarks;
# analyze.py computes relative overheads.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

EXECUTOR_SCRIPT="$REPO_ROOT/exec/${EXECUTOR:-qemu}.sh"
LEAVES=(fio concurrency sqlite)

# ==============================================================================
# 1. Clean Initialization
# ==============================================================================
# Reset leaf result logs and remove previous raw benchmark outputs
# so analysis runs strictly against the current execution.
for leaf in "${LEAVES[@]}"; do
    : > "$SCRIPT_DIR/$leaf/result.log"
    rm -rf "$SCRIPT_DIR/$leaf/raw"
done

# ==============================================================================
# 2. Consolidated Variant Execution
# ==============================================================================
run_variant() {
    local variant_label="$1"
    local kernel_variant="$2"
    local pks_mode="$3"
    local transcript_log="$SCRIPT_DIR/raw-${variant_label}.log"

    echo "--- [perf] Launching variant: $variant_label ($kernel_variant, pks=$pks_mode) ---"
    "$EXECUTOR_SCRIPT" "$kernel_variant" "$pks_mode" perf "$transcript_log"

    for leaf in "${LEAVES[@]}"; do
        harvest_node "$transcript_log" "$leaf" "$SCRIPT_DIR/$leaf/result.log"
    done
}

run_variant control control off
run_variant off     perf    off
run_variant on      perf    on

# ==============================================================================
# 3. Validation, Rollup, and Analysis
# ==============================================================================
for leaf in "${LEAVES[@]}"; do
    mark_empty_leaves all "$SCRIPT_DIR/$leaf/result.log"
done

rollup "$SCRIPT_DIR/result.log" perf "$SCRIPT_DIR"/*/result.log
rollup_rc=$?

# Extract summary metrics into results CSV
python3 "$SCRIPT_DIR/analyze.py" "$SCRIPT_DIR" "$REPO_ROOT/results/data/perf_summary.csv" || true

exit "$rollup_rc"

