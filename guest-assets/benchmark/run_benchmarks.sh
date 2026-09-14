#!/usr/bin/env bash
# ==============================================================================
# guest-assets/benchmark/run_benchmarks.sh - Buffered I/O scaling benchmark suite
# ==============================================================================
set -euo pipefail

PROTECTED_MOUNT="/mnt/protected"
BENCH_DIR="$PROTECTED_MOUNT/bench_data"
RESULTS_DIR="${RESULTS_DIR:-$PROTECTED_MOUNT/bench_results}"
FILE_SIZE="${FILE_SIZE:-64M}"
RUNS="${RUNS:-5}"

mkdir -p "$RESULTS_DIR"

# 1. Mount verification
if ! mountpoint -q "$PROTECTED_MOUNT"; then
    echo "[INFO] Mounting $PROTECTED_MOUNT..."
    mkdir -p "$PROTECTED_MOUNT"
    if [ -b /dev/vda2 ]; then
        mount /dev/vda2 "$PROTECTED_MOUNT" 2>/dev/null || mount -t ext4 /dev/vda2 "$PROTECTED_MOUNT" 2>/dev/null || true
    fi
fi

if ! mountpoint -q "$PROTECTED_MOUNT"; then
    echo "[ERR]  $PROTECTED_MOUNT is not mounted and /dev/vda2 not found."
    exit 1
fi

mkdir -p "$BENCH_DIR"

if grep "$PROTECTED_MOUNT" /proc/mounts | grep -q "pks_pagecache"; then
    echo "[OK]   Evaluating MITIGATED state (pks_pagecache active)"
else
    echo "[INFO] Evaluating CONTROL state (standard unprotected ext4)"
fi

drop_caches() {
    sync
    echo 3 > /proc/sys/vm/drop_caches
}

echo ""
echo "================================================================"
echo " Benchmark Configuration"
echo "   Mount Point:  $PROTECTED_MOUNT"
echo "   File Size:    $FILE_SIZE"
echo "   Iterations:   $RUNS"
echo "   Output Dir:   $RESULTS_DIR"
echo "================================================================"

# Workload 1: Synchronous Buffered Write Scaling (4KB to 1MB)
echo ""
echo "==> Workload 1: Synchronous Buffered Write Scaling"
for bs in 4k 16k 64k 256k 1024k; do
    echo "  --> Testing block size $bs ($RUNS runs)..."
    for i in $(seq 1 "$RUNS"); do
        drop_caches
        out_file="$RESULTS_DIR/write_${bs}_run${i}.json"
        fio --name=seq_write_sync \
            --directory="$BENCH_DIR" \
            --rw=write \
            --bs="$bs" \
            --size="$FILE_SIZE" \
            --ioengine=sync \
            --direct=0 \
            --numjobs=1 \
            --group_reporting \
            --output-format=json \
            --output="$out_file" >/dev/null 2>&1
        rm -f "$BENCH_DIR"/seq_write_sync*
    done
    echo "  [OK] Block size $bs complete"
done

# Workload 2: Synchronous Buffered Random Read Parity (4KB)
echo ""
echo "==> Workload 2: Synchronous Buffered Random Read Parity (4KB)"
drop_caches
echo "  --> Pre-allocating read target file ($FILE_SIZE)..."
fio --name=read_prep \
    --directory="$BENCH_DIR" \
    --rw=write \
    --bs=1m \
    --size="$FILE_SIZE" \
    --ioengine=sync \
    --direct=0 >/dev/null 2>&1

echo "  --> Testing random read 4KB ($RUNS runs)..."
for i in $(seq 1 "$RUNS"); do
    drop_caches
    out_file="$RESULTS_DIR/read_4k_run${i}.json"
    fio --name=rand_read_sync \
        --directory="$BENCH_DIR" \
        --rw=randread \
        --bs=4k \
        --size="$FILE_SIZE" \
        --ioengine=sync \
        --direct=0 \
        --numjobs=1 \
        --group_reporting \
        --output-format=json \
        --output="$out_file" >/dev/null 2>&1
done
echo "  [OK] Random read parity complete"

# Cleanup benchmark scratch files to release pool memory
rm -rf "$BENCH_DIR"/*
drop_caches
sync

# Mirror to /tmp/bench_results in case callers expect it there
mkdir -p /tmp/bench_results
cp -a "$RESULTS_DIR"/* /tmp/bench_results/ 2>/dev/null || true

echo ""
echo "================================================================"
echo " [OK] Benchmarking complete. Results stored in: $RESULTS_DIR"
echo "================================================================"
