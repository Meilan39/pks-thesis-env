#!/bin/bash
set -euo pipefail

# ============================================================
# PKS Benchmark Suite: Synchronous Buffered File I/O
# Run as root: sudo ./run_benchmarks.sh
# ============================================================

PROTECTED_MOUNT="/mnt/protected"
BENCH_DIR="$PROTECTED_MOUNT/bench_data"
RESULTS_DIR="${RESULTS_DIR:-/tmp/bench_results}"
FILE_SIZE="${FILE_SIZE:-64M}"
RUNS="${RUNS:-5}"

mkdir -p "$RESULTS_DIR"

# 1. Mount verification
if ! mountpoint -q "$PROTECTED_MOUNT"; then
    echo "Mounting $PROTECTED_MOUNT..."
    mkdir -p "$PROTECTED_MOUNT"
    if [ -b /dev/vda2 ]; then
        mount /dev/vda2 "$PROTECTED_MOUNT" 2>/dev/null || mount -t ext4 /dev/vda2 "$PROTECTED_MOUNT" 2>/dev/null || true
    fi
fi

if ! mountpoint -q "$PROTECTED_MOUNT"; then
    echo "ERROR: $PROTECTED_MOUNT is not mounted and /dev/vda2 not found."
    exit 1
fi

mkdir -p "$BENCH_DIR"

IS_PKS=0
if grep "$PROTECTED_MOUNT" /proc/mounts | grep -q "pks_pagecache"; then
    IS_PKS=1
    echo "[+] Evaluating MITIGATED state (pks_pagecache active)"
else
    echo "[-] Evaluating CONTROL state (unprotected ext4)"
fi

drop_caches() {
    sync
    echo 3 > /proc/sys/vm/drop_caches
}

echo "======================================================="
echo " Benchmark Configuration:"
echo "   Mount point:  $PROTECTED_MOUNT"
echo "   File size:    $FILE_SIZE"
echo "   Iterations:   $RUNS"
echo "   Output dir:   $RESULTS_DIR"
echo "======================================================="

# Workload 1: Synchronous Buffered Write Scaling (4KB to 1MB)
echo ""
echo "=== Workload 1: Buffered Write Scaling ==="
for bs in 4k 16k 64k 256k 1024k; do
    echo ">>> Testing bs=$bs (file size=$FILE_SIZE) <<<"
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
            --output="$out_file"
        rm -f "$BENCH_DIR"/seq_write_sync*
    done
done

# Workload 2: Synchronous Buffered Random Read Parity (4KB)
echo ""
echo "=== Workload 2: 4KB Random Read Parity ==="
drop_caches
echo "Pre-allocating read target file ($FILE_SIZE)..."
fio --name=read_prep \
    --directory="$BENCH_DIR" \
    --rw=write \
    --bs=1m \
    --size="$FILE_SIZE" \
    --ioengine=sync \
    --direct=0 > /dev/null

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
        --output="$out_file"
done

# Cleanup bench files to release pool memory
rm -rf "$BENCH_DIR"/*
drop_caches

echo ""
echo "======================================================="
echo " Benchmarking complete."
echo " Results stored in: $RESULTS_DIR"
echo "======================================================="
