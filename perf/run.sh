#!/usr/bin/env bash
# perf/run.sh - In-guest combined performance benchmark dispatcher
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIANT="${1:-on}"

"$SCRIPT_DIR/fio/run_warm.sh" "$VARIANT"
"$SCRIPT_DIR/fio/run_cold.sh" "$VARIANT"
"$SCRIPT_DIR/concurrency/run.sh" "$VARIANT"
"$SCRIPT_DIR/sqlite/run.sh" "$VARIANT"
