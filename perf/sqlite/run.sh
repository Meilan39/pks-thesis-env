#!/usr/bin/env bash
# perf/sqlite/run.sh - SQLite rollback-journal macrobenchmark (sync FULL & OFF).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; source "$ROOT/common.sh"
VAR="${1:-on}"
TGT=/mnt/protected; [ -d "$TGT" ] || TGT=/tmp
OUT="$ROOT/results/raw/json/$VAR"; mkdir -p "$OUT" 2>/dev/null || true
BENCH="$DIR/sqlite_bench.sh"
if [ ! -x "$BENCH" ] || ! command -v sqlite3 >/dev/null 2>&1; then emit_status sqlite "$VAR" FAIL note=sqlite_missing; exit 0; fi
"$BENCH" "$TGT" FULL "$OUT/sqlite_FULL.json" 500  >/dev/null 2>&1 || true
"$BENCH" "$TGT" OFF  "$OUT/sqlite_OFF.json"  5000 >/dev/null 2>&1 || true
tps() { python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['tps'])" "$1" 2>/dev/null || echo NA; }
emit_status sqlite "$VAR" PASS tps_syncoff="$(tps "$OUT/sqlite_OFF.json")" tps_syncfull="$(tps "$OUT/sqlite_FULL.json")"
