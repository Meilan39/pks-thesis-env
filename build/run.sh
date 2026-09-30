#!/usr/bin/env bash
# build/run.sh - aggregate the three kernel builds and roll up. The human log is
# streamed live to the console and archived to build/<v>/raw.log by build_kernel;
# result.log holds only the STATUS line, consistent with every other node.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/.." && pwd)"
source "$ROOT/common.sh"
for v in control sec perf; do
    tmp="$(mktemp)"
    "$DIR/$v/run.sh" 2>&1 | tee "$tmp"
    _status_lines "$tmp" > "$DIR/$v/result.log"
    rm -f "$tmp"
done
rollup "$DIR/result.log" build "$DIR/control/result.log" "$DIR/sec/result.log" "$DIR/perf/result.log"
