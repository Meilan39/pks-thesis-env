#!/usr/bin/env bash
# perf/run.sh - HOST aggregator for the performance axis. One consolidated boot
# per experimental variant: control (baseline kernel), off (mitigated kernel,
# PKS disabled = ablation), on (mitigated kernel, PKS enabled). Leaves emit real
# metrics parsed from their own fio/sqlite JSON; analyze.py computes overhead.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/.." && pwd)"
source "$ROOT/common.sh"
EXEC="$ROOT/exec/${EXECUTOR:-qemu}.sh"
LEAVES=(fio concurrency sqlite)

for l in "${LEAVES[@]}"; do : > "$DIR/$l/result.log"; done

# One consolidated boot per variant; its transcript is axis-level.
# variant  kernel_variant  pks_mode
run_variant() {
    local label="$1" kvar="$2" mode="$3"
    local T="$DIR/raw-${label}.log"
    "$EXEC" "$kvar" "$mode" perf "$T"
    local l; for l in "${LEAVES[@]}"; do harvest_node "$T" "$l" "$DIR/$l/result.log"; done
}
run_variant control control off
run_variant off     perf    off
run_variant on      perf    on

for l in "${LEAVES[@]}"; do mark_empty_leaves all "$DIR/$l/result.log"; done
rollup "$DIR/result.log" perf "$DIR"/*/result.log
rc=$?
# JSON now lives leaf-local at perf/<leaf>/raw/<variant>/; analyze reads from there.
python3 "$DIR/analyze.py" "$DIR" "$ROOT/results/data/perf_summary.csv" || true
exit $rc
