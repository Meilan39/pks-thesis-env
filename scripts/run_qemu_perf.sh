#!/usr/bin/env bash
# ==============================================================================
# scripts/run_qemu_perf.sh - Mitigated performance benchmark launcher
# ==============================================================================
# Usage: ./run_qemu_perf.sh [--batch|--interactive]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_KERNEL="$(cd "$SCRIPT_DIR/../../linux-5.18-rc3" 2>/dev/null && pwd || true)"

DEV_KERNEL_DIR="${DEV_KERNEL_DIR:-${WORKSPACE_KERNEL:-$HOME/src/linux-pks-thesis}}"
DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
SMP="${SMP:-4}"
CONSOLE="${CONSOLE:-ttyS0}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
TASKSET_CPUS="${TASKSET_CPUS:-}"
TOTAL_MEM="${MEM_PERF_MITIGATED:-4096M}"
RESULTS_DIR="${RESULTS_DIR:-$ENV_DIR/results}"

RUN_MODE="${1:---interactive}"

KERNEL="$DEV_KERNEL_DIR/build_perf/arch/x86/boot/bzImage"
[ -f "$KERNEL" ] || die "Performance kernel not found at $KERNEL. Run 'make build-perf' first."
[ -f "$DISK_IMG" ] || die "Disk image not found at $DISK_IMG. Run 'make provision-disk' first."
require_cmds "$QEMU_BIN"

# CPU virtualization mode
CPU_ARGS=()
CPU_MODE=""
if [ -e /dev/kvm ] && grep -qw pks /proc/cpuinfo; then
    CPU_MODE="KVM / host (Hardware PKS verified)"
    CPU_ARGS=(-enable-kvm -cpu host)
elif [ -e /dev/kvm ]; then
    CPU_MODE="KVM / host (Host lacks PKS, falling back to TCG)"
    CPU_ARGS=(-cpu max,pks=on)
    log_warn "Host CPU lacks supervisor PKS; benchmark latencies under TCG will not be representative."
else
    CPU_MODE="TCG / max,pks=on"
    CPU_ARGS=(-cpu max,pks=on)
    log_warn "KVM not available; using TCG. Micro-benchmark results will not be representative."
fi

TASKSET_CMD=()
if [ -n "$TASKSET_CPUS" ]; then
    TASKSET_CMD=(taskset -c "$TASKSET_CPUS")
fi

EXTRA_CMDLINE=""
LOG_FILE=""
if [ "$RUN_MODE" = "--batch" ]; then
    mkdir -p "$RESULTS_DIR"
    LOG_FILE="$RESULTS_DIR/perf_mitigated.log"
    EXTRA_CMDLINE="pks_auto=bench panic=1"
fi

log_header "Launching Mitigated Performance Benchmark VM"
log_kv "Kernel"      "$KERNEL"
log_kv "Disk Image"  "$DISK_IMG"
log_kv "Execution"   "$RUN_MODE"
log_kv "PKS State"   "on"
log_kv "Total RAM"   "$TOTAL_MEM (256MB pool -> 3840MB usable)"
log_kv "CPU Mode"    "$CPU_MODE"
log_kv "CPU Pinning" "${TASKSET_CPUS:-none}"
if [ -n "$LOG_FILE" ]; then
    log_kv "Serial Log"  "$LOG_FILE"
fi

QEMU_CMD=(
    "${TASKSET_CMD[@]}"
    "$QEMU_BIN"
    -machine q35
    "${CPU_ARGS[@]}"
    -smp "$SMP"
    -m "$TOTAL_MEM"
    -kernel "$KERNEL"
    -append "root=/dev/vda1 rw console=$CONSOLE nokaslr pcache_pks=on $EXTRA_CMDLINE"
    -drive file="$DISK_IMG",format=raw,if=virtio,cache=none,aio=native
    -nographic
    -no-reboot
)

if [ "$RUN_MODE" = "--batch" ]; then
    log_step "Running automated batch benchmark (logging to $LOG_FILE)..."
    "${QEMU_CMD[@]}" 2>&1 | tee "$LOG_FILE"
    log_ok "Mitigated benchmark run finished"
else
    "${QEMU_CMD[@]}"
fi