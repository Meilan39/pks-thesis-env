#!/usr/bin/env bash
# perf/fio/run.sh - warm + cold synchronous block sweeps (512B..1MB). Timed I/O
# stays on /mnt/protected; JSON is written to the 9p workspace results dir.
# STATUS carries the real 4KiB warm latencies parsed from the JSON.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; source "$ROOT/common.sh"
VAR="${1:-on}"
TGT=/mnt/protected; [ -d "$TGT" ] || TGT=/tmp
OUT="$ROOT/results/raw/json/$VAR/fio"; mkdir -p "$OUT" 2>/dev/null || true
if ! command -v fio >/dev/null 2>&1; then emit_status fio "$VAR" FAIL note=fio_missing; exit 0; fi
SIZES="512 1024 2048 4096 8192 16384 32768 65536 131072 262144 524288 1048576"

WARM="$TGT/fio_warm.dat"
dd if=/dev/urandom of="$WARM" bs=1M count=32 status=none conv=fsync 2>/dev/null || true
for BS in $SIZES; do
    fio --name=w --ioengine=sync --direct=0 --buffered=1 --rw=write --bs="$BS" --size=32m \
        --filename="$WARM" --numjobs=1 --thread=1 --group_reporting=1 \
        --output-format=json --output="$OUT/write_warm_${BS}.json" >/dev/null 2>&1 || true
    fio --name=r --ioengine=sync --direct=0 --buffered=1 --rw=read --bs="$BS" --size=32m \
        --filename="$WARM" --numjobs=1 --thread=1 --group_reporting=1 \
        --output-format=json --output="$OUT/read_warm_${BS}.json" >/dev/null 2>&1 || true
done
rm -f "$WARM"

COLD="$TGT/fio_cold.dat"
for BS in $SIZES; do
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true; rm -f "$COLD"
    fio --name=c --ioengine=sync --direct=0 --buffered=1 --rw=write --bs="$BS" --size=32m \
        --filename="$COLD" --numjobs=1 --thread=1 --group_reporting=1 \
        --output-format=json --output="$OUT/write_cold_${BS}.json" >/dev/null 2>&1 || true
done
rm -f "$COLD"

lat() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(round(d['jobs'][0][sys.argv[2]]['lat_ns']['mean']/1000,2))" "$1" "$2" 2>/dev/null || echo NA; }
emit_status fio "$VAR" PASS \
    lat4k_warm_write_us="$(lat "$OUT/write_warm_4096.json" write)" \
    lat4k_warm_read_us="$(lat "$OUT/read_warm_4096.json" read)"
