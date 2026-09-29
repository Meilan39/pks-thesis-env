#!/usr/bin/env bash
# perf/sqlite/sqlite_bench.sh - SQLite rollback journal macrobenchmark
set -euo pipefail

TARGET_DIR="${1:-/mnt/protected}"
SYNC_MODE="${2:-FULL}"
OUTPUT_JSON="${3:-/tmp/sqlite_${SYNC_MODE}.json}"  # always overridden by run.sh
TX_COUNT="${4:-5000}"

command -v sqlite3 >/dev/null 2>&1 || { echo "[WARN] sqlite3 not found, skipping."; exit 0; }
DB_FILE="${TARGET_DIR}/sqlite_bench_${SYNC_MODE}.db"
mkdir -p "$(dirname "$OUTPUT_JSON")"
rm -f "$DB_FILE" "${DB_FILE}-journal"

echo "[INFO] Running SQLite benchmark (synchronous=$SYNC_MODE, transactions=$TX_COUNT) on $TARGET_DIR..."

START_NS=$(date +%s%N)
{
    echo "PRAGMA journal_mode=DELETE; PRAGMA mmap_size=0; PRAGMA synchronous=${SYNC_MODE};"
    echo "CREATE TABLE IF NOT EXISTS kv_bench (id INTEGER PRIMARY KEY, key_name TEXT, val_data TEXT);"
    python3 -c "for i in range(1, int('$TX_COUNT')+1): print(f'BEGIN; INSERT INTO kv_bench VALUES ({i}, \"k{i}\", \"payload_{i}\"); COMMIT;')"
} | sqlite3 "$DB_FILE" >/dev/null
END_NS=$(date +%s%N)

ELAPSED_NS=$(( END_NS - START_NS ))
[ "$ELAPSED_NS" -le 0 ] && ELAPSED_NS=1
rm -f "$DB_FILE" "${DB_FILE}-journal"

python3 -c "
import json
tx, ns, sm = int('$TX_COUNT'), int('$ELAPSED_NS'), '$SYNC_MODE'
tps = (tx * 1e9) / ns
lat = float(ns) / tx
json.dump({'workload': 'sqlite_macro', 'sync_mode': sm, 'transactions': tx, 'elapsed_ns': ns, 'tps': round(tps,2), 'latency_ns': round(lat,2)}, open('$OUTPUT_JSON', 'w'), indent=2)
print(f'[INFO] SQLite ({sm}): {tx} txns in {ns/1e9:.3f}s -> {tps:.2f} TPS, {lat:.1f} ns/tx')
"

chmod 644 "$OUTPUT_JSON"
exit 0
