#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# Performance Benchmark Launcher - Development Kernel (pcache_pks=on)
# Usage: ./run_qemu_perf.sh
#
# This script boots the mitigated kernel for the "implementation" run.
# It uses KVM if available; otherwise falls back to TCG (not recommended
# for performance measurements).
#
# Memory handicap: The control VM boots with mem=3840M (no pool reserved).
# The mitigated VM boots with mem=4096M (kernel reserves 256M pool),
# leaving 3840M usable, matching the control environment.
# ----------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_KERNEL="$(cd "$SCRIPT_DIR/../../linux-5.18-rc3" 2>/dev/null && pwd || true)"

DEV_KERNEL_DIR="${DEV_KERNEL_DIR:-${WORKSPACE_KERNEL:-$HOME/src/linux-pks-thesis}}"
DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
SMP="${SMP:-4}"
CONSOLE="${CONSOLE:-ttyS0}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
TASKSET_CPUS="${TASKSET_CPUS:-}"          # optional, e.g., "4-7"

# CPU pinning
if [ -n "$TASKSET_CPUS" ]; then
    TASKSET_CMD="taskset -c $TASKSET_CPUS"
else
    TASKSET_CMD=""
fi

TOTAL_MEM="${TOTAL_MEM:-4096M}"           # 4G total, 256M reserved for pool

KERNEL="$DEV_KERNEL_DIR/build_perf/arch/x86/boot/bzImage"
[ -f "$KERNEL" ] || { echo "Error: Kernel not found at $KERNEL. Run build_perf.sh first."; exit 1; }
[ -f "$DISK_IMG" ] || { echo "Error: Disk image not found at $DISK_IMG"; exit 1; }

# CPU mode
CPU_ARGS=()
MODE=""
if [ -e /dev/kvm ]; then
    MODE="KVM / host"
    CPU_ARGS=(-enable-kvm -cpu host)
else
    MODE="TCG / max"
    CPU_ARGS=(-cpu max)
    echo "WARNING: KVM not available, using TCG. Performance numbers will be meaningless."
fi

echo "-----------------------------------------------------"
echo " Performance Benchmark Boot (Mitigated Kernel)"
echo "   Kernel:      $KERNEL"
echo "   Disk:        $DISK_IMG"
echo "   PKS state:   on"
echo "   Total RAM:   $TOTAL_MEM"
echo "   CPU mode:    $MODE"
echo "   CPU pinning: ${TASKSET_CPUS:-none}"
echo "-----------------------------------------------------"

$TASKSET_CMD "$QEMU_BIN" \
    -machine q35 \
    "${CPU_ARGS[@]}" \
    -smp "$SMP" \
    -m "$TOTAL_MEM" \
    -kernel "$KERNEL" \
    -append "root=/dev/vda1 rw console=$CONSOLE nokaslr pcache_pks=on" \
    -drive file="$DISK_IMG",format=raw,if=virtio,cache=none,aio=native \
    -nographic \
    -no-reboot