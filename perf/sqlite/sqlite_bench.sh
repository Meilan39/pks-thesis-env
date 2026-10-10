#!/usr/bin/env bash
# ==============================================================================
# perf/sqlite/sqlite_bench.sh - SQLite Rollback Journal Benchmark Worker
# ==============================================================================
# Usage:
#   sqlite_bench.sh [target_dir] [sync_mode] [output_json] [tx_count]
#
# Arguments:
#   target_dir  : Filesystem path to host the database file (e.g. /mnt/protected)
#   sync_mode   : SQLite PRAGMA synchronous mode (FULL or OFF)
#   output_json : Destination path for machine-readable JSON telemetry
#   tx_count    : Total number of discrete commit transactions to execute
# ==============================================================================
set -euo pipefail

TARGET_DIR="${1:-/mnt/protected}"
SYNC_MODE="${2:-FULL}"
OUTPUT_JSON="${3:-/tmp/sqlite_${SYNC_MODE}.json}"
TX_COUNT="${4:-5000}"

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "[WARN] sqlite3 command not found; skipping." >&2
    exit 0
fi

DB_FILE="${TARGET_DIR}/sqlite_bench_${SYNC_MODE}.db"
mkdir -p "$(dirname "$OUTPUT_JSON")"
rm -f "$DB_FILE" "${DB_FILE}-journal"

echo "[INFO] Running SQLite benchmark (synchronous=$SYNC_MODE, transactions=$TX_COUNT) on $TARGET_DIR..."

# ------------------------------------------------------------------------------
# Timed transaction execution
# ------------------------------------------------------------------------------
START_NS=$(date +%s%N)
{
    echo "PRAGMA journal_mode=DELETE;"
    echo "PRAGMA mmap_size=0;"
    echo "PRAGMA synchronous=${SYNC_MODE};"
    echo "CREATE TABLE IF NOT EXISTS kv_bench (id INTEGER PRIMARY KEY, key_name TEXT, val_data TEXT);"
    python3 -c "
for i in range(1, int('$TX_COUNT') + 1):
    print(f'BEGIN; INSERT INTO kv_bench VALUES ({i}, \"k{i}\", \"payload_{i}\"); COMMIT;')
"
} | sqlite3 "$DB_FILE" >/dev/null
END_NS=$(date +%s%N)

ELAPSED_NS=$(( END_NS - START_NS ))
if [ "$ELAPSED_NS" -le 0 ]; then
    ELAPSED_NS=1
fi

rm -f "$DB_FILE" "${DB_FILE}-journal"

# ------------------------------------------------------------------------------
# Compute metrics & export JSON
# ------------------------------------------------------------------------------
python3 -c "
import json

tx_count = int('$TX_COUNT')
elapsed_ns = int('$ELAPSED_NS')
sync_mode = '$SYNC_MODE'

tps = (tx_count * 1e9) / elapsed_ns
latency_ns = float(elapsed_ns) / tx_count

telemetry = {
    'workload': 'sqlite_macro',
    'sync_mode': sync_mode,
    'transactions': tx_count,
    'elapsed_ns': elapsed_ns,
    'tps': round(tps, 2),
    'latency_ns': round(latency_ns, 1)
}

with open('$OUTPUT_JSON', 'w') as f:
    json.dump(telemetry, f, indent=2)

print(f'[INFO] SQLite ({sync_mode}): {tx_count} txns in {elapsed_ns / 1e9:.3f}s -> {tps:.2f} TPS, {latency_ns:.1f} ns/tx')
"

chmod 644 "$OUTPUT_JSON"
exit 0
