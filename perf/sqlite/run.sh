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
TMP_FULL="/tmp/sqlite_${VARIANT}_FULL.json"
TMP_OFF="/tmp/sqlite_${VARIANT}_OFF.json"

# synchronous=FULL (500 transactions)
"$BENCH_SCRIPT" "$TARGET_DIR" FULL "$TMP_FULL" 500 >/dev/null 2>&1 || true

# synchronous=OFF (5,000 transactions)
"$BENCH_SCRIPT" "$TARGET_DIR" OFF "$TMP_OFF" 5000 >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# 3. Telemetry Extraction and Verdict
# ------------------------------------------------------------------------------
extract_field() {
    local json_file="$1"
    local field="$2"
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get(sys.argv[2], 'NA'))
except Exception:
    print('NA')
" "$json_file" "$field" 2>/dev/null || echo "NA"
}

tps_syncoff="$(extract_field "$TMP_OFF" tps)"
tps_syncfull="$(extract_field "$TMP_FULL" tps)"

lat_syncoff_us="$(python3 -c "
import json
try:
    with open('$TMP_OFF') as f:
        d = json.load(f)
    print(round(float(d['latency_ns']) / 1000.0, 2))
except Exception:
    print('NA')
" 2>/dev/null || echo "NA")"

lat_syncfull_us="$(python3 -c "
import json
try:
    with open('$TMP_FULL') as f:
        d = json.load(f)
    print(round(float(d['latency_ns']) / 1000.0, 2))
except Exception:
    print('NA')
" 2>/dev/null || echo "NA")"

rm -f "$TMP_FULL" "$TMP_OFF"

emit_status sqlite "$VARIANT" PASS \
    tps_syncoff="$tps_syncoff" \
    tps_syncfull="$tps_syncfull" \
    lat_syncoff_us="$lat_syncoff_us" \
    lat_syncfull_us="$lat_syncfull_us"
