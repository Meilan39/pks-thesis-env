#!/usr/bin/env bash
# perf/fio/run.sh - Combined warm & cold fio sweep runner
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIANT="${1:-on}"

"$SCRIPT_DIR/run_warm.sh" "$VARIANT"
"$SCRIPT_DIR/run_cold.sh" "$VARIANT"
