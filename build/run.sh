#!/usr/bin/env bash
# build/run.sh - aggregate the three kernel builds and roll up.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/.." && pwd)"
source "$ROOT/common.sh"
for v in control sec perf; do
    "$DIR/$v/run.sh" 2>&1 | tee "$DIR/$v/result.log"
done
rollup "$DIR/result.log" build "$DIR/control/result.log" "$DIR/sec/result.log" "$DIR/perf/result.log"
