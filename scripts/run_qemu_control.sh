#!/usr/bin/env bash
# ==============================================================================
# scripts/run_qemu_control.sh - Vanilla upstream control benchmark launcher
# ==============================================================================
# Usage: ./run_qemu_control.sh [--batch|--interactive]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_CONTROL="$(cd "$SCRIPT_DIR/../../linux-control" 2>/dev/null && pwd || true)"
WORKSPACE_CONTROL_ALT="$(cd "$SCRIPT_DIR/../../linux-pks-thesis-control" 2>/dev/null && pwd || true)"

CONTROL_KERNEL_DIR="${CONTROL_KERNEL_DIR:-${WORKSPACE_CONTROL:-${WORKSPACE_CONTROL_ALT:-$HOME/src/linux-pks-thesis-control}}}"
DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
SMP="${SMP:-4}"
CONSOLE="${CONSOLE:-ttyS0}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
TASKSET_CPUS="${TASKSET_CPUS:-}"
MEM="${MEM_PERF_CONTROL:-3840M}"
RESULTS_DIR="${RESULTS_DIR:-$ENV_DIR/results}"

RUN_MODE="${1:---interactive}"

KERNEL="$CONTROL_KERNEL_DIR/build_perf/arch/x86/boot/bzImage"
[ -f "$KERNEL" ] || die "Control kernel not found at $KERNEL. Run 'make build-control' first."
[ -f "$DISK_IMG" ] || die "Disk image not found at $DISK_IMG. Run 'make provision-image' first."
require_cmds "$QEMU_BIN"

# CPU virtualization mode
CPU_ARGS=()
CPU_MODE=""
if [ -e /dev/kvm ]; then
    CPU_MODE="KVM / host"
    CPU_ARGS=(-enable-kvm -cpu host)
else
    CPU_MODE="TCG / max"
    CPU_ARGS=(-cpu max)
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
    LOG_FILE="$RESULTS_DIR/perf_control.log"
    EXTRA_CMDLINE="pks_auto=bench panic=1"
fi

log_header "Launching Control Baseline Benchmark VM"
log_kv "Kernel"      "$KERNEL"
log_kv "Disk Image"  "$DISK_IMG"
log_kv "Execution"   "$RUN_MODE"
log_kv "Total RAM"   "$MEM (Equalized to mitigated usable RAM)"
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
    -m "$MEM"
    -kernel "$KERNEL"
    -append "root=/dev/vda1 rw console=$CONSOLE nokaslr $EXTRA_CMDLINE"
    -drive file="$DISK_IMG",format=raw,if=virtio,cache=none,aio=native
    -nographic
    -no-reboot
)

if [ "$RUN_MODE" = "--batch" ]; then
    log_step "Running automated batch benchmark (logging to $LOG_FILE)..."
    "${QEMU_CMD[@]}" 2>&1 | tee "$LOG_FILE"
    log_ok "Control baseline benchmark run finished"
else
    "${QEMU_CMD[@]}"
fi