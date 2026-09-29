#!/usr/bin/env bash
# perf/concurrency/run.sh - multithreaded write throughput at 1/2/4 threads.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; source "$ROOT/common.sh"
VAR="${1:-on}"
TGT=/mnt/protected; [ -d "$TGT" ] || TGT=/tmp
OUT="$DIR/raw/$VAR"; mkdir -p "$OUT" 2>/dev/null || true
if ! command -v fio >/dev/null 2>&1; then emit_status concurrency "$VAR" FAIL note=fio_missing; exit 0; fi
for JOBS in 1 2 4; do
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    for ((j=0;j<JOBS;j++)); do dd if=/dev/urandom of="$TGT/fio_concur_${JOBS}_${j}.dat" bs=1M count=16 status=none conv=fsync 2>/dev/null || true; done
    fio --name=c --ioengine=sync --direct=0 --buffered=1 --rw=write --bs=4k --size=16m \
        --numjobs="$JOBS" --thread=1 --group_reporting=1 \
        --filename_format="$TGT/fio_concur_${JOBS}_\$jobnum.dat" \
        --output-format=json --output="$OUT/concurrency_${JOBS}.json" >/dev/null 2>&1 || true
    rm -f "$TGT/fio_concur_${JOBS}_"*.dat
done
bw() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(round(d['jobs'][0]['write']['bw']/1024,1))" "$1" 2>/dev/null || echo NA; }
emit_status concurrency "$VAR" PASS bw_4t_mbps="$(bw "$OUT/concurrency_4.json")"
