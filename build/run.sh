#!/usr/bin/env bash
# build/run.sh - Aggregates the three kernel builds and rolls up status.
# Console output is streamed live and archived to build/<variant>/raw.log;
# result.log holds only the STATUS lines, consistent with all axis nodes.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

VARIANTS=(control sec perf)

# ==============================================================================
# 1. Sequential Kernel Compilation
# ==============================================================================
for variant in "${VARIANTS[@]}"; do
    tmp_output="$(mktemp)"
    "$SCRIPT_DIR/$variant/run.sh" 2>&1 | tee "$tmp_output"
    _status_lines "$tmp_output" > "$SCRIPT_DIR/$variant/result.log"
    rm -f "$tmp_output"
done

# ==============================================================================
# 2. Status Rollup
# ==============================================================================
rollup "$SCRIPT_DIR/result.log" build \
    "$SCRIPT_DIR/control/result.log" \
    "$SCRIPT_DIR/sec/result.log" \
    "$SCRIPT_DIR/perf/result.log"

