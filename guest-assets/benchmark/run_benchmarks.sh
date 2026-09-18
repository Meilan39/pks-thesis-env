#!/usr/bin/env bash
# ==============================================================================
# guest-assets/benchmark/run_benchmarks.sh
#
# Consolidated in-guest performance benchmark orchestrator.
# Implements the evaluation plan from context/benchmark-plan-2.md:
#   1. Detects kernel variant (baseline_control, mitigated_off, mitigated_on).
#   2. Warm-cache multi-syscall sweep (write, read, ftruncate: 512B - 1MiB).
#   3. Cold-cache multi-syscall sweep (first-touch write, ftruncate: 512B - 1MiB).
#   4. Multi-core concurrency scaling (numjobs = 1, 2, 4 with private files).
#   5. SQLite macrobenchmark (PRAGMA synchronous = FULL vs OFF).
#   6. Provenance logging (meminfo, cpuinfo, cmdline, steal time).
#
# Outputs structured raw JSON metrics to /mnt/protected/bench_results/raw/<variant>/
# ==============================================================================

set -euo pipefail

# 1. Determine Target Mount & Working Directory
BENCH_DIR="/mnt/protected"
if ! mountpoint -q "${BENCH_DIR}"; then
    if [ -d /mnt/scratch ]; then
        BENCH_DIR="/mnt/scratch"
    else
        BENCH_DIR="/tmp/bench_scratch"
        mkdir -p "${BENCH_DIR}"
    fi
    echo "[WARN] /mnt/protected not mounted. Falling back to ${BENCH_DIR}"
else
    echo "[INFO] Evaluating on protected mount: ${BENCH_DIR}"
fi

# 2. Identify Kernel Evaluation Variant
CMDLINE=$(cat /proc/cmdline 2>/dev/null || echo "")
if [[ "${CMDLINE}" == *"pcache_pks=on"* ]]; then
    KERNEL_VARIANT="mitigated_on"
elif [[ "${CMDLINE}" == *"pcache_pks=off"* ]]; then
    KERNEL_VARIANT="mitigated_off"
else
    KERNEL_VARIANT="baseline_control"
fi

RAW_OUT_DIR="${BENCH_DIR}/bench_results/raw/${KERNEL_VARIANT}"
mkdir -p "${RAW_OUT_DIR}"

echo "======================================================================"
echo " Starting PKS Performance Benchmark Suite"
echo " Kernel Variant: ${KERNEL_VARIANT}"
echo " Kernel Release: $(uname -r)"
echo " Output Dir:     ${RAW_OUT_DIR}"
echo " Date:           $(date)"
echo "======================================================================"

# 3. Tune VM parameters to avoid background writeback jitter
sysctl -w vm.dirty_ratio=80 >/dev/null 2>&1 || true
sysctl -w vm.dirty_background_ratio=60 >/dev/null 2>&1 || true

# Helper to capture meminfo snapshot
capture_meminfo() {
    local tag="$1"
    grep -E "(Dirty|Writeback|MemFree|MemAvailable|Cached):" /proc/meminfo > "${RAW_OUT_DIR}/meminfo_${tag}.txt"
}

BLOCK_SIZES=(512 1024 2048 4096 8192 16384 32768 65536 131072 262144 524288 1048576)

# ==============================================================================
# Phase 1: Warm-Cache Multi-Syscall Sweep (512 B - 1 MiB)
# ==============================================================================
echo ""
echo "=== [1/4] Executing Warm-Cache Multi-Syscall Sweep ==="
WARM_FILE="${BENCH_DIR}/fio_warm.dat"
TRUNC_WARM_FILE="${BENCH_DIR}/fio_trunc_warm.dat"

# Pre-allocate and pre-warm working files to 64 MiB
echo "[INFO] Pre-allocating 64 MiB warm working files..."
dd if=/dev/urandom of="${WARM_FILE}" bs=1M count=64 status=none conv=fsync
dd if=/dev/urandom of="${TRUNC_WARM_FILE}" bs=1M count=64 status=none conv=fsync

capture_meminfo "warm_before"

for BS in "${BLOCK_SIZES[@]}"; do
    echo "  -> Warm sweep: block_size=${BS} bytes"

    # Buffered write (in-memory overwrite)
    fio --name=warm_write \
        --ioengine=sync \
        --direct=0 \
        --buffered=1 \
        --rw=write \
        --bs="${BS}" \
        --size=64m \
        --filename="${WARM_FILE}" \
        --numjobs=1 \
        --thread=1 \
        --group_reporting=1 \
        --output-format=json \
        --output="${RAW_OUT_DIR}/fio_write_warm_${BS}.json" >/dev/null 2>&1

    # Buffered read (zero permission toggles)
    fio --name=warm_read \
        --ioengine=sync \
        --direct=0 \
        --buffered=1 \
        --rw=read \
        --bs="${BS}" \
        --size=64m \
        --filename="${WARM_FILE}" \
        --numjobs=1 \
        --thread=1 \
        --group_reporting=1 \
        --output-format=json \
        --output="${RAW_OUT_DIR}/fio_read_warm_${BS}.json" >/dev/null 2>&1

    # Truncate sweep via native fio ftruncate engine
    fio --name=warm_truncate \
        --ioengine=ftruncate \
        --rw=write \
        --bs="${BS}" \
        --size=64m \
        --filename="${TRUNC_WARM_FILE}" \
        --numjobs=1 \
        --thread=1 \
        --group_reporting=1 \
        --output-format=json \
        --output="${RAW_OUT_DIR}/fio_truncate_warm_${BS}.json" >/dev/null 2>&1
done

capture_meminfo "warm_after"
rm -f "${WARM_FILE}" "${TRUNC_WARM_FILE}"

# ==============================================================================
# Phase 2: Cold-Cache Multi-Syscall Sweep (512 B - 1 MiB)
# ==============================================================================
echo ""
echo "=== [2/4] Executing Cold-Cache Multi-Syscall Sweep ==="
COLD_FILE="${BENCH_DIR}/fio_cold.dat"
TRUNC_COLD_FILE="${BENCH_DIR}/fio_trunc_cold.dat"

capture_meminfo "cold_before"

for BS in "${BLOCK_SIZES[@]}"; do
    echo "  -> Cold sweep: block_size=${BS} bytes"

    # Evict page cache before first-touch allocation
    sync
    echo 3 > /proc/sys/vm/drop_caches
    rm -f "${COLD_FILE}"

    # Cold write: triggers static pool folio allocation
    fio --name=cold_write \
        --ioengine=sync \
        --direct=0 \
        --buffered=1 \
        --rw=write \
        --bs="${BS}" \
        --size=64m \
        --filename="${COLD_FILE}" \
        --numjobs=1 \
        --thread=1 \
        --group_reporting=1 \
        --output-format=json \
        --output="${RAW_OUT_DIR}/fio_write_cold_${BS}.json" >/dev/null 2>&1

    # Cold truncate via native fio ftruncate engine
    sync
    echo 3 > /proc/sys/vm/drop_caches
    rm -f "${TRUNC_COLD_FILE}"
    fio --name=cold_truncate \
        --ioengine=ftruncate \
        --rw=write \
        --bs="${BS}" \
        --size=64m \
        --filename="${TRUNC_COLD_FILE}" \
        --numjobs=1 \
        --thread=1 \
        --group_reporting=1 \
        --output-format=json \
        --output="${RAW_OUT_DIR}/fio_truncate_cold_${BS}.json" >/dev/null 2>&1
done

capture_meminfo "cold_after"
rm -f "${COLD_FILE}" "${TRUNC_COLD_FILE}"

# ==============================================================================
# Phase 3: Multi-Core Concurrency Scaling (numjobs = 1, 2, 4)
# ==============================================================================
echo ""
echo "=== [3/4] Executing Multi-Core Concurrency Sweep ==="
for JOBS in 1 2 4; do
    echo "  -> Concurrency test: numjobs=${JOBS} (private files, bs=4K)"

    # Pre-allocate thread-private files
    for ((j=0; j<JOBS; j++)); do
        dd if=/dev/urandom of="${BENCH_DIR}/fio_concur_${JOBS}_${j}.dat" bs=1M count=64 status=none conv=fsync
    done

    fio --name=concurrency_sweep \
        --ioengine=sync \
        --direct=0 \
        --buffered=1 \
        --rw=write \
        --bs=4k \
        --size=64m \
        --numjobs="${JOBS}" \
        --thread=1 \
        --group_reporting=1 \
        --filename_format="${BENCH_DIR}/fio_concur_${JOBS}_%n.dat" \
        --output-format=json \
        --output="${RAW_OUT_DIR}/fio_concurrency_jobs_${JOBS}.json" >/dev/null 2>&1

    rm -f ${BENCH_DIR}/fio_concur_${JOBS}_*.dat
done

# ==============================================================================
# Phase 4: SQLite Macrobenchmark (Rollback Journal Mode)
# ==============================================================================
echo ""
echo "=== [4/4] Executing SQLite Macrobenchmark ==="
SQLITE_SCRIPT="/benchmark/sqlite_bench.sh"
if [ -x "${SQLITE_SCRIPT}" ]; then
    "${SQLITE_SCRIPT}" "${BENCH_DIR}" FULL "${RAW_OUT_DIR}/sqlite_FULL.json" 5000
    "${SQLITE_SCRIPT}" "${BENCH_DIR}" OFF "${RAW_OUT_DIR}/sqlite_OFF.json" 5000
else
    echo "[WARN] sqlite_bench.sh not found or not executable. Skipping macrobenchmark."
fi

# ==============================================================================
# Phase 5: Environmental Provenance & Metadata Recording
# ==============================================================================
echo ""
echo "=== Recording Environment Provenance Metadata ==="
python3 -c "
import json, platform, subprocess, time

def get_cmd_output(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True).strip()
    except Exception as e:
        return str(e)

metadata = {
    'kernel_variant': '${KERNEL_VARIANT}',
    'kernel_release': platform.release(),
    'kernel_version': platform.version(),
    'cmdline': get_cmd_output('cat /proc/cmdline'),
    'cpu_model': get_cmd_output('grep \"model name\" /proc/cpuinfo | head -n 1 | cut -d: -f2').strip(),
    'cpu_count': int(get_cmd_output('nproc')),
    'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'mount_options': get_cmd_output('mount | grep \"${BENCH_DIR}\"'),
    'steal_time_stat': get_cmd_output('grep \"cpu \" /proc/stat')
}

with open('${RAW_OUT_DIR}/run_metadata.json', 'w') as f:
    json.dump(metadata, f, indent=2)

print('[INFO] Metadata captured in ${RAW_OUT_DIR}/run_metadata.json')
"

# Copy results to /tmp/bench_results/raw/<variant> as secondary backup
mkdir -p "/tmp/bench_results/raw/${KERNEL_VARIANT}"
cp -a "${RAW_OUT_DIR}/." "/tmp/bench_results/raw/${KERNEL_VARIANT}/" 2>/dev/null || true

sync
echo "======================================================================"
echo " Benchmark suite execution successfully completed!"
echo " Outputs archived in: ${RAW_OUT_DIR}"
echo "======================================================================"
exit 0
