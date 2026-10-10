#!/usr/bin/env bash
# ==============================================================================
# perf/fio/run.sh - Synchronous block I/O microbenchmark (warm & cold sweeps)
# ==============================================================================
# Single-threaded read/write latency across 512B-1MB block sizes under
# synchronous, page-cached I/O: a warm sweep (in-cache file) and a cold sweep
# (caches dropped between runs). Emits the 4KiB latencies parsed from fio JSON.
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
# Dependencies
# ------------------------------------------------------------------------------
if ! command -v fio >/dev/null 2>&1; then
    emit_status fio "$VARIANT" FAIL note=fio_missing
    exit 0
fi

BLOCK_SIZES="512 1024 2048 4096 8192 16384 32768 65536 131072 262144 524288 1048576"

# Tune dirty ratios to avoid writeback stalls during 32MB microbenchmark bursts
ORIG_DIRTY_BG="$(cat /proc/sys/vm/dirty_background_ratio 2>/dev/null || echo 10)"
ORIG_DIRTY_RATIO="$(cat /proc/sys/vm/dirty_ratio 2>/dev/null || echo 20)"
echo 50 > /proc/sys/vm/dirty_background_ratio 2>/dev/null || true
echo 80 > /proc/sys/vm/dirty_ratio 2>/dev/null || true
cleanup_dirty() {
    echo "$ORIG_DIRTY_BG" > /proc/sys/vm/dirty_background_ratio 2>/dev/null || true
    echo "$ORIG_DIRTY_RATIO" > /proc/sys/vm/dirty_ratio 2>/dev/null || true
}
trap cleanup_dirty EXIT

# ------------------------------------------------------------------------------
# Warm sweep: in-cache overwrite
# ------------------------------------------------------------------------------
# Pre-populate the 32MB file in memory using fast zeroing
WARM_FILE="$TARGET_DIR/fio_warm.dat"
dd if=/dev/zero of="$WARM_FILE" bs=1M count=32 status=none 2>/dev/null || true
sync

for bs in $BLOCK_SIZES; do
    # Invalidate=0 and overwrite=1 ensure fio modifies cached pages in place
    fio --name=warm_write \
        --ioengine=sync \
        --direct=0 \
        --buffered=1 \
        --rw=write \
        --overwrite=1 \
        --invalidate=0 \
        --bs="$bs" \
        --size=32m \
        --filename="$WARM_FILE" \
        --numjobs=1 \
        --thread=1 \
        --group_reporting=1 \
        --output-format=json \
        --output="$RAW_DIR/write_warm_${bs}.json" >/dev/null 2>&1 || true

    fio --name=warm_read \
        --ioengine=sync \
        --direct=0 \
        --buffered=1 \
        --rw=read \
        --invalidate=0 \
        --bs="$bs" \
        --size=32m \
        --filename="$WARM_FILE" \
        --numjobs=1 \
        --thread=1 \
        --group_reporting=1 \
        --output-format=json \
        --output="$RAW_DIR/read_warm_${bs}.json" >/dev/null 2>&1 || true

    # Clean dirty pages so subsequent block sizes do not contend with writeback
    sync
done
rm -f "$WARM_FILE"

# ------------------------------------------------------------------------------
# Cold sweep: caches dropped prior to allocation
# ------------------------------------------------------------------------------
COLD_FILE="$TARGET_DIR/fio_cold.dat"
for bs in $BLOCK_SIZES; do
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    rm -f "$COLD_FILE"

    fio --name=cold_write \
        --ioengine=sync \
        --direct=0 \
        --buffered=1 \
        --rw=write \
        --invalidate=1 \
        --bs="$bs" \
        --size=32m \
        --filename="$COLD_FILE" \
        --numjobs=1 \
        --thread=1 \
        --group_reporting=1 \
        --output-format=json \
        --output="$RAW_DIR/write_cold_${bs}.json" >/dev/null 2>&1 || true

    sync
done
rm -f "$COLD_FILE"

# ------------------------------------------------------------------------------
# Extract telemetry & emit
# ------------------------------------------------------------------------------
extract_metric() {
    local json_file="$1"
    local expr="$2"
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    val = $expr
    print(round(float(val), 2))
except Exception:
    print('NA')
" "$json_file" 2>/dev/null || echo "NA"
}

warm_write_4k_lat="$(extract_metric "$RAW_DIR/write_warm_4096.json" "d['jobs'][0]['write']['lat_ns']['mean'] / 1000.0")"
warm_read_4k_lat="$(extract_metric "$RAW_DIR/read_warm_4096.json" "d['jobs'][0]['read']['lat_ns']['mean'] / 1000.0")"
cold_write_4k_lat="$(extract_metric "$RAW_DIR/write_cold_4096.json" "d['jobs'][0]['write']['lat_ns']['mean'] / 1000.0")"
warm_write_4k_iops="$(extract_metric "$RAW_DIR/write_warm_4096.json" "d['jobs'][0]['write']['iops']")"
read_1m_bw="$(extract_metric "$RAW_DIR/read_warm_1048576.json" "d['jobs'][0]['read']['bw']")"

alloc_overhead="$(python3 -c "
try:
    cold = float('$cold_write_4k_lat')
    warm = float('$warm_write_4k_lat')
    print(round(cold - warm, 2))
except Exception:
    print('NA')
" 2>/dev/null || echo "NA")"

emit_status fio "$VARIANT" PASS \
    iops4k_warm_write="$warm_write_4k_iops" \
    lat4k_warm_write_us="$warm_write_4k_lat" \
    lat4k_warm_read_us="$warm_read_4k_lat" \
    lat4k_cold_write_us="$cold_write_4k_lat" \
    alloc_overhead_us="$alloc_overhead" \
    bw1m_seq_read_kbs="$read_1m_bw"
