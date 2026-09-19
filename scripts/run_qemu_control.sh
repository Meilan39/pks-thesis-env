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
CONTROL_KERNEL_DIR="${CONTROL_KERNEL_DIR:-$HOME/src/linux-pks-thesis-control}"
DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
SMP="${SMP:-4}"
CONSOLE="${CONSOLE:-ttyS0}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
TASKSET_CPUS="${TASKSET_CPUS:-}"
MEM="${MEM_PERF_CONTROL:-3840M}"
RESULTS_DIR="${RESULTS_DIR:-$ENV_DIR/results}"

RUN_MODE="${1:---interactive}"

if [ -f "$CONTROL_KERNEL_DIR/build_perf/arch/x86/boot/bzImage" ]; then
    KERNEL="$CONTROL_KERNEL_DIR/build_perf/arch/x86/boot/bzImage"
elif [ -f "$CONTROL_KERNEL_DIR/build_control/arch/x86/boot/bzImage" ]; then
    KERNEL="$CONTROL_KERNEL_DIR/build_control/arch/x86/boot/bzImage"
else
    KERNEL="$CONTROL_KERNEL_DIR/build_perf/arch/x86/boot/bzImage"
fi
[ -f "$KERNEL" ] || die "Control kernel not found at $KERNEL. Run 'make build-control' first."
[ -f "$DISK_IMG" ] || die "Disk image not found at $DISK_IMG. Run 'make provision-disk' first."
require_cmds "$QEMU_BIN"

# CPU virtualization mode
QEMU_ACCEL="${QEMU_ACCEL:-auto}"
CPU_ARGS=()
CPU_MODE=""
if [ "$QEMU_ACCEL" = "kvm" ]; then
    CPU_MODE="KVM / host (Forced KVM)"
    CPU_ARGS=(-enable-kvm -cpu host)
elif [ "$QEMU_ACCEL" = "tcg" ]; then
    CPU_MODE="TCG / max (Forced TCG)"
    CPU_ARGS=(-cpu max)
elif [ -e /dev/kvm ] && grep -qw pks /proc/cpuinfo; then
    CPU_MODE="KVM / host (Hardware PKS verified)"
    CPU_ARGS=(-enable-kvm -cpu host)
elif [ -e /dev/kvm ]; then
    CPU_MODE="TCG / max (Host lacks PKS, matching perf VM TCG mode)"
    CPU_ARGS=(-cpu max)
    log_warn "Host CPU lacks supervisor PKS. Running control in TCG mode to match perf VM execution environment."
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
    RAW_LOG_FILE="$RESULTS_DIR/raw_perf_control.log"
    EXTRA_CMDLINE="pks_auto=bench panic=1 systemd.mask=serial-getty@ttyS0.service systemd.mask=getty.target"
fi

log_header "Launching Control Baseline Benchmark VM"
log_kv "Kernel"      "$KERNEL"
log_kv "Disk Image"  "$DISK_IMG"
log_kv "Execution"   "$RUN_MODE"
log_kv "Total RAM"   "$MEM (Equalized to mitigated usable RAM)"
log_kv "CPU Mode"    "$CPU_MODE"
log_kv "CPU Pinning" "${TASKSET_CPUS:-none}"
if [ -n "$LOG_FILE" ]; then
    log_kv "Clean Log"   "$LOG_FILE"
    log_kv "Raw Serial"  "$RAW_LOG_FILE"
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
    log_step "Executing control VM (raw output to $RAW_LOG_FILE)..."
    "${QEMU_CMD[@]}" > "$RAW_LOG_FILE" 2>&1 || true
    
    # Filter out early boot noise, keeping autorun banner onward + any panic traces
    awk '
        /\[PKS AUTORUN\]|=== \[/ { capturing = 1 }
        capturing { print; next }
        /Kernel panic|Oops|Call Trace:|Security event|BUG:|CR4:|MSR IA32_PKRS|do_trap/ { print }
    ' "$RAW_LOG_FILE" > "$LOG_FILE"
    
    if [ ! -s "$LOG_FILE" ]; then
        cp "$RAW_LOG_FILE" "$LOG_FILE"
    fi
    log_ok "Control baseline run finished. Report: $LOG_FILE"
else
    "${QEMU_CMD[@]}"
fi