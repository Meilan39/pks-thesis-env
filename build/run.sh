#!/usr/bin/env bash
# ==============================================================================
# build/run.sh - Build axis aggregator
# ==============================================================================
# Compiles the three kernels, streaming each live to build/<variant>/raw.log and
# distilling its STATUS lines into build/<variant>/result.log, then rolls up.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

VARIANTS=(control sec perf)

# ------------------------------------------------------------------------------
# Compile each variant
# ------------------------------------------------------------------------------
for variant in "${VARIANTS[@]}"; do
    tmp_output="$(mktemp)"
    "$SCRIPT_DIR/$variant/run.sh" 2>&1 | tee "$tmp_output"
    _status_lines "$tmp_output" > "$SCRIPT_DIR/$variant/result.log"
    rm -f "$tmp_output"
done

# ------------------------------------------------------------------------------
# Roll up
# ------------------------------------------------------------------------------
rollup "$SCRIPT_DIR/result.log" build \
    "$SCRIPT_DIR/control/result.log" \
    "$SCRIPT_DIR/sec/result.log" \
    "$SCRIPT_DIR/perf/result.log"
