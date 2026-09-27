#!/usr/bin/env bash
# ==============================================================================
# guest-assets/benchmark/sqlite_bench.sh
#
# SQLite macrobenchmark evaluating rollback journal mode on protected mounts.
# Tests Commit 06 compatibility boundaries:
#   PRAGMA journal_mode = DELETE;
#   PRAGMA mmap_size = 0;
# Evaluated under PRAGMA synchronous = FULL and synchronous = OFF.
# Emits structured JSON metrics for TPS and average transaction latency.
# ==============================================================================

set -euo pipefail

TARGET_DIR="${1:-/mnt/protected}"
SYNC_MODE="${2:-FULL}" # FULL or OFF
OUTPUT_JSON="${3:-/mnt/protected/bench_results/raw/sqlite_${SYNC_MODE}.json}"
TX_COUNT="${4:-5000}"

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "[WARN] sqlite3 command not found. Skipping SQLite benchmark."
    exit 0
fi

DB_FILE="${TARGET_DIR}/sqlite_bench_${SYNC_MODE}.db"

mkdir -p "$(dirname "${OUTPUT_JSON}")"
rm -f "${DB_FILE}" "${DB_FILE}-journal"

echo "[INFO] Running SQLite benchmark (synchronous=${SYNC_MODE}, transactions=${TX_COUNT}) on ${TARGET_DIR}..."

# Generate SQL script
SQL_SCRIPT=$(mktemp)
cat <<EOF > "${SQL_SCRIPT}"
PRAGMA journal_mode = DELETE;
PRAGMA mmap_size = 0;
PRAGMA synchronous = ${SYNC_MODE};

CREATE TABLE IF NOT EXISTS kv_bench (
    id INTEGER PRIMARY KEY,
    key_name TEXT,
    val_data TEXT
);
EOF

# Pre-populate SQL with individual transactions
# Each transaction creates, writes to journal, commits, and unlinks/truncates journal.
python3 -c "
tx_count = int('${TX_COUNT}')
with open('${SQL_SCRIPT}', 'a') as f:
    for i in range(1, tx_count + 1):
        f.write('BEGIN TRANSACTION;\n')
        f.write(f'INSERT INTO kv_bench (id, key_name, val_data) VALUES ({i}, \'key_{i}\', \'payload_data_string_for_pks_pagecache_scoping_{i}\');\n')
        f.write('COMMIT;\n')
"

START_NS=$(date +%s%N)
sqlite3 "${DB_FILE}" < "${SQL_SCRIPT}"
END_NS=$(date +%s%N)

rm -f "${SQL_SCRIPT}"
rm -f "${DB_FILE}" "${DB_FILE}-journal"

ELAPSED_NS=$((END_NS - START_NS))
if [ "${ELAPSED_NS}" -le 0 ]; then
    ELAPSED_NS=1
fi

python3 -c "
import json

tx_count = int('${TX_COUNT}')
elapsed_ns = int('${ELAPSED_NS}')
sync_mode = '${SYNC_MODE}'
out_file = '${OUTPUT_JSON}'

tps = (tx_count * 1_000_000_000.0) / elapsed_ns
avg_latency_ns = float(elapsed_ns) / tx_count

data = {
    'workload': 'sqlite_macro',
    'sync_mode': sync_mode,
    'transactions': tx_count,
    'elapsed_ns': elapsed_ns,
    'tps': round(tps, 2),
    'latency_ns': round(avg_latency_ns, 2)
}

with open(out_file, 'w') as f:
    json.dump(data, f, indent=2)

print(f'[INFO] SQLite ({sync_mode}): {tx_count} txns in {elapsed_ns/1e9:.3f}s -> {tps:.2f} TPS, {avg_latency_ns:.1f} ns/tx')
"

chmod 644 "${OUTPUT_JSON}"
exit 0
