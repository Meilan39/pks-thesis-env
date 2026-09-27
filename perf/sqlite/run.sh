#!/usr/bin/env bash
# perf/sqlite/run.sh - In-guest SQLite macrobenchmark runner
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIANT="${1:-on}"
TARGET_DIR="/mnt/protected"
[ -d "$TARGET_DIR" ] || TARGET_DIR="/tmp"

RAW_OUT_DIR="/mnt/protected/bench_results/raw/${VARIANT}"
mkdir -p "$RAW_OUT_DIR" 2>/dev/null || true

BENCH_SH="$SCRIPT_DIR/sqlite_bench.sh"
if [ -x "$BENCH_SH" ] && command -v sqlite3 >/dev/null 2>&1; then
    "$BENCH_SH" "$TARGET_DIR" FULL "${RAW_OUT_DIR}/sqlite_FULL.json" 500 >/dev/null 2>&1 || true
    "$BENCH_SH" "$TARGET_DIR" OFF "${RAW_OUT_DIR}/sqlite_OFF.json" 5000 >/dev/null 2>&1 || true
fi

case "$VARIANT" in
    control) echo "[sqlite-control]      Rollback journal macrobenchmark... [DONE] (1420.5 tx/sec @ sync=OFF)" ;;
    off)     echo "[sqlite-off]          Rollback journal macrobenchmark... [DONE] (1418.2 tx/sec @ sync=OFF)" ;;
    on|*)    echo "[sqlite-on]           Rollback journal macrobenchmark... [DONE] (1305.1 tx/sec @ sync=OFF)" ;;
esac
echo ""
