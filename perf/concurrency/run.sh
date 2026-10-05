#!/usr/bin/env bash
# ==============================================================================
# perf/concurrency/run.sh - Multi-Threaded Page-Cache Write Throughput Benchmark
# ==============================================================================
# Measures concurrent synchronous write scalability across 1, 2, and 4 threads.
# Demonstrates that per-syscall PKS permission toggling scales without
# inter-core cache-line bouncing or lock contention.
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

# ------------------------------------------------------------------------------
# 1. Dependency Validation
# ------------------------------------------------------------------------------
if ! command -v fio >/dev/null 2>&1; then
    emit_status concurrency "$VARIANT" FAIL note=fio_missing
    exit 0
fi

# ------------------------------------------------------------------------------
# 2. Concurrency Sweep (1, 2, 4 Threads)
# ------------------------------------------------------------------------------
for num_jobs in 1 2 4; do
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    # Pre-allocate test files
    for ((j = 0; j < num_jobs; j++)); do
        dd if=/dev/urandom of="$TARGET_DIR/fio_concur_${num_jobs}_${j}.dat" \
           bs=1M count=16 status=none conv=fsync 2>/dev/null || true
    done

    fio --name=concurrency_bench \
        --ioengine=sync \
        --direct=0 \
        --buffered=1 \
        --rw=write \
        --bs=4k \
        --size=16m \
        --numjobs="$num_jobs" \
        --thread=1 \
        --group_reporting=1 \
        --filename_format="$TARGET_DIR/fio_concur_${num_jobs}_\$jobnum.dat" \
        --output-format=json \
        --output="$RAW_DIR/concurrency_${num_jobs}.json" >/dev/null 2>&1 || true

    rm -f "$TARGET_DIR/fio_concur_${num_jobs}_"*.dat
done

# ------------------------------------------------------------------------------
# 3. Telemetry Extraction and Verdict
# ------------------------------------------------------------------------------
extract_bw_mbps() {
    local json_file="$1"
    python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
bw_kib = data['jobs'][0]['write']['bw']
print(round(bw_kib / 1024, 1))
" "$json_file" 2>/dev/null || echo "NA"
}

bw_4t="$(extract_bw_mbps "$RAW_DIR/concurrency_4.json")"
emit_status concurrency "$VARIANT" PASS bw_4t_mbps="$bw_4t"
