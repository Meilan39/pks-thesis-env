#!/usr/bin/env bash
# ==============================================================================
# scripts/run_qemu_sec.sh - Security validation launcher (off/on)
# ==============================================================================
# Usage: ./run_qemu_sec.sh <off|on> [--batch|--interactive]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_KERNEL="$(cd "$SCRIPT_DIR/../../linux-5.18-rc3" 2>/dev/null && pwd || true)"

DEV_KERNEL_DIR="${DEV_KERNEL_DIR:-${WORKSPACE_KERNEL:-$HOME/src/linux-pks-thesis}}"
DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
MEM="${MEM_SEC:-4G}"
SMP="${SMP:-4}"
CONSOLE="${CONSOLE:-ttyS0}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
RESULTS_DIR="${RESULTS_DIR:-$ENV_DIR/results}"

if [ $# -lt 1 ] || [[ "$1" != "off" && "$1" != "on" ]]; then
    echo "Usage: $0 <off|on> [--batch|--interactive]"
    exit 1
fi
PKS_STATE="$1"
RUN_MODE="${2:---interactive}"

KERNEL="$DEV_KERNEL_DIR/build_sec/arch/x86/boot/bzImage"
[ -f "$KERNEL" ] || die "Security kernel not found at $KERNEL. Run 'make build-sec' first."
[ -f "$DISK_IMG" ] || die "Disk image not found at $DISK_IMG. Run 'make provision-disk' first."
require_cmds "$QEMU_BIN"

# Determine CPU virtualization mode
CPU_ARGS=()
CPU_MODE=""
if [ -e /dev/kvm ] && grep -qw pks /proc/cpuinfo; then
    CPU_MODE="KVM / host (Hardware PKS verified)"
    CPU_ARGS=(-enable-kvm -cpu host)
elif [ -e /dev/kvm ]; then
    CPU_MODE="TCG / max,vendor=GenuineIntel,pks=on (Host lacks PKS, falling back to TCG)"
    CPU_ARGS=(-cpu max,vendor=GenuineIntel,pks=on)
    log_warn "Host CPU lacks supervisor PKS; falling back to TCG emulation."
else
    CPU_MODE="TCG / max,vendor=GenuineIntel,pks=on"
    CPU_ARGS=(-cpu max,vendor=GenuineIntel,pks=on)
    log_warn "KVM not available; using TCG emulation (functional only, not publication-grade)."
fi

EXTRA_CMDLINE=""
LOG_FILE=""
if [ "$RUN_MODE" = "--batch" ]; then
    AUTO_MODE="${3:-sec}"
    mkdir -p "$RESULTS_DIR"
    if [ "$AUTO_MODE" = "unit" ]; then
        LOG_FILE="$RESULTS_DIR/pks_unit.log"
    elif [ "$AUTO_MODE" = "fsx" ]; then
        LOG_FILE="$RESULTS_DIR/fsx_${PKS_STATE}.log"
    elif [ "$AUTO_MODE" = "sec" ]; then
        LOG_FILE="$RESULTS_DIR/sec_${PKS_STATE}.log"
    else
        LOG_FILE="$RESULTS_DIR/${AUTO_MODE}_${PKS_STATE}.log"
    fi
    EXTRA_CMDLINE="pks_auto=$AUTO_MODE panic=1 systemd.mask=serial-getty@ttyS0.service systemd.mask=getty.target"
fi

log_header "Launching Security Validation Boot"
log_kv "PKS State"   "$PKS_STATE"
log_kv "Execution"   "$RUN_MODE"
log_kv "Kernel"      "$KERNEL"
log_kv "Disk Image"  "$DISK_IMG"
log_kv "CPU Mode"    "$CPU_MODE"
log_kv "RAM / Cores" "$MEM / $SMP"
if [ -n "$LOG_FILE" ]; then
    log_kv "Serial Log"  "$LOG_FILE"
fi

QEMU_CMD=(
    "$QEMU_BIN"
    -machine q35
    "${CPU_ARGS[@]}"
    -smp "$SMP"
    -m "$MEM"
    -kernel "$KERNEL"
    -append "root=/dev/vda1 rw console=$CONSOLE nokaslr pcache_pks=$PKS_STATE $EXTRA_CMDLINE"
    -drive file="$DISK_IMG",format=raw,if=virtio,cache=none,aio=native
    -nographic
    -no-reboot
)

if [ "$RUN_MODE" = "--batch" ]; then
    log_step "Running automated batch security validation (logging to $LOG_FILE)..."
    "${QEMU_CMD[@]}" 2>&1 | tee "$LOG_FILE"
    log_ok "Batch execution finished for pcache_pks=$PKS_STATE"
else
    "${QEMU_CMD[@]}"
fi