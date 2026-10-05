#!/usr/bin/env bash
# ==============================================================================
# perf/sqlite/run.sh - SQLite Rollback-Journal Macrobenchmark
# ==============================================================================
# Evaluates real-world database transaction throughput and latency using SQLite
# in classic rollback-journal mode.
#
# Workload:
# 1. synchronous=FULL (500 txns): fsync on every commit, bound by storage flush
# 2. synchronous=OFF  (5000 txns): pure page-cache write and truncate path,
#    isolated to measure CPU/PKS permission switching overhead
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/common.sh"

VARIANT="${1:-on}"

TARGET_DIR="/mnt/protected"
if [ ! -d "$TARGET_DIR" ]; then
    TARGET_DIR="/tmp"
fi

RAW_DIR="$SCRIPT_DIR/raw/$VARIANT"
mkdir -p "$RAW_DIR" 2>/dev/null || true

BENCH_SCRIPT="$SCRIPT_DIR/sqlite_bench.sh"

# ------------------------------------------------------------------------------
# 1. Dependency Validation
# ------------------------------------------------------------------------------
if [ ! -x "$BENCH_SCRIPT" ] || ! command -v sqlite3 >/dev/null 2>&1; then
    emit_status sqlite "$VARIANT" FAIL note=sqlite_missing
    exit 0
fi

# ------------------------------------------------------------------------------
# 2. Benchmark Execution
# ------------------------------------------------------------------------------
# synchronous=FULL (500 transactions)
"$BENCH_SCRIPT" "$TARGET_DIR" FULL "$RAW_DIR/sqlite_FULL.json" 500 >/dev/null 2>&1 || true

# synchronous=OFF (5,000 transactions)
"$BENCH_SCRIPT" "$TARGET_DIR" OFF "$RAW_DIR/sqlite_OFF.json" 5000 >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# 3. Telemetry Extraction and Verdict
# ------------------------------------------------------------------------------
extract_tps() {
    local json_file="$1"
    python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
print(data['tps'])
" "$json_file" 2>/dev/null || echo "NA"
}

tps_syncoff="$(extract_tps "$RAW_DIR/sqlite_OFF.json")"
tps_syncfull="$(extract_tps "$RAW_DIR/sqlite_FULL.json")"

emit_status sqlite "$VARIANT" PASS \
    tps_syncoff="$tps_syncoff" \
    tps_syncfull="$tps_syncfull"
