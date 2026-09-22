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
DEV_KERNEL_DIR="${DEV_KERNEL_DIR:-$HOME/src/linux-pks-thesis}"
DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
SMP="${SMP:-4}"
CONSOLE="${CONSOLE:-ttyS0}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
TASKSET_CPUS="${TASKSET_CPUS:-}"
TOTAL_MEM="${MEM_PERF_MITIGATED:-4096M}"
RESULTS_DIR="${RESULTS_DIR:-$ENV_DIR/results}"
BENCH_RUNS="${BENCH_RUNS:-5}"

RUN_MODE="${1:---interactive}"
PKS_STATE="${2:-on}"

KERNEL="$DEV_KERNEL_DIR/build_perf/arch/x86/boot/bzImage"
[ -f "$KERNEL" ] || die "Performance kernel not found at $KERNEL. Run 'make build-perf' first."
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
    CPU_MODE="TCG / max,vendor=GenuineIntel,pks=on (Forced TCG)"
    CPU_ARGS=(-cpu max,vendor=GenuineIntel,pks=on)
elif [ -e /dev/kvm ] && grep -qw pks /proc/cpuinfo; then
    CPU_MODE="KVM / host (Hardware PKS verified)"
    CPU_ARGS=(-enable-kvm -cpu host)
elif [ -e /dev/kvm ]; then
    CPU_MODE="TCG / max,vendor=GenuineIntel,pks=on (Host lacks PKS, falling back to TCG)"
    CPU_ARGS=(-cpu max,vendor=GenuineIntel,pks=on)
    log_warn "Host CPU lacks supervisor PKS; benchmark latencies under TCG will not be representative."
else
    CPU_MODE="TCG / max,vendor=GenuineIntel,pks=on"
    CPU_ARGS=(-cpu max,vendor=GenuineIntel,pks=on)
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
    if [ "$PKS_STATE" = "off" ]; then
        LOG_FILE="$RESULTS_DIR/perf_mitigated_off.log"
        RAW_LOG_FILE="$RESULTS_DIR/raw_perf_mitigated_off.log"
    else
        LOG_FILE="$RESULTS_DIR/perf_mitigated.log"
        RAW_LOG_FILE="$RESULTS_DIR/raw_perf_mitigated.log"
    fi
    EXTRA_CMDLINE="pks_auto=bench pks_runs=$BENCH_RUNS panic=1 systemd.mask=serial-getty@ttyS0.service systemd.mask=getty.target"
fi

log_header "Launching Mitigated Performance Benchmark VM"
log_kv "Kernel"      "$KERNEL"
log_kv "Disk Image"  "$DISK_IMG"
log_kv "Execution"   "$RUN_MODE"
log_kv "Iterations"  "$BENCH_RUNS runs"
log_kv "PKS State"   "$PKS_STATE"
log_kv "Total RAM"   "$TOTAL_MEM (256MB pool -> 3840MB usable)"
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
    -m "$TOTAL_MEM"
    -kernel "$KERNEL"
    -append "root=/dev/vda1 rw console=$CONSOLE nokaslr pcache_pks=$PKS_STATE $EXTRA_CMDLINE"
    -drive file="$DISK_IMG",format=raw,if=virtio,cache=none,aio=native
    -nographic
    -no-reboot
)

if [ "$RUN_MODE" = "--batch" ]; then
    log_step "Executing mitigated VM (raw output to $RAW_LOG_FILE)..."
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
    log_ok "Mitigated benchmark run finished. Report: $LOG_FILE"
else
    "${QEMU_CMD[@]}"
fi