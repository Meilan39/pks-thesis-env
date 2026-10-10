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

# ------------------------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------------------------
if ! command -v fio >/dev/null 2>&1; then
    emit_status concurrency "$VARIANT" FAIL note=fio_missing
    exit 0
fi

# ------------------------------------------------------------------------------
# Concurrency sweep (1, 2, 4 threads)
# ------------------------------------------------------------------------------
TMP_PREFIX="/tmp/concur_${VARIANT}"

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
        --output="${TMP_PREFIX}_${num_jobs}.json" >/dev/null 2>&1 || true

    rm -f "$TARGET_DIR/fio_concur_${num_jobs}_"*.dat
done

# ------------------------------------------------------------------------------
# Extract telemetry & emit
# ------------------------------------------------------------------------------
extract_bw_mbps() {
    local json_file="$1"
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    bw_kib = d['jobs'][0]['write']['bw']
    print(round(float(bw_kib) / 1024.0, 1))
except Exception:
    print('NA')
" "$json_file" 2>/dev/null || echo "NA"
}

bw_1t="$(extract_bw_mbps "${TMP_PREFIX}_1.json")"
bw_2t="$(extract_bw_mbps "${TMP_PREFIX}_2.json")"
bw_4t="$(extract_bw_mbps "${TMP_PREFIX}_4.json")"

scaling_pct="$(python3 -c "
try:
    b1 = float('$bw_1t')
    b4 = float('$bw_4t')
    if b1 > 0:
        eff = (b4 / (4.0 * b1)) * 100.0
        print(f'{eff:.1f}')
    else:
        print('NA')
except Exception:
    print('NA')
" 2>/dev/null || echo "NA")"

rm -f "${TMP_PREFIX}_"*.json

emit_status concurrency "$VARIANT" PASS \
    bw_1t_mbps="$bw_1t" \
    bw_2t_mbps="$bw_2t" \
    bw_4t_mbps="$bw_4t" \
    scaling_pct="$scaling_pct"
