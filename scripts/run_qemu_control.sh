#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# Performance Benchmark Launcher - Control Kernel
# Usage: ./run_qemu_control.sh
#
# Boots the vanilla upstream control kernel for baseline performance.
# Uses KVM if available; otherwise falls back to TCG (not recommended).
# ----------------------------------------------------------------------

# User-configurable variables
CONTROL_KERNEL_DIR="${CONTROL_KERNEL_DIR:-$HOME/src/linux-pks-thesis-control}"
DISK_IMG="${DISK_IMG:-$HOME/src/env/images/disk.img}"
SMP="${SMP:-4}"
CONSOLE="${CONSOLE:-ttyS0}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
TASKSET_CPUS="${TASKSET_CPUS:-}"

if [ -n "$TASKSET_CPUS" ]; then
    TASKSET_CMD="taskset -c $TASKSET_CPUS"
else
    TASKSET_CMD=""
fi

MEM="${MEM:-3840M}"    # 3.75G usable to match mitigated VM after pool reservation

KERNEL="$CONTROL_KERNEL_DIR/build_perf/arch/x86/boot/bzImage"
[ -f "$KERNEL" ] || { echo "Error: Control kernel not found at $KERNEL. Run build_control.sh first."; exit 1; }
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
echo " Performance Benchmark Boot (Control Kernel)"
echo "   Kernel:      $KERNEL"
echo "   Disk:        $DISK_IMG"
echo "   Total RAM:   $MEM"
echo "   CPU mode:    $MODE"
echo "   CPU pinning: ${TASKSET_CPUS:-none}"
echo "-----------------------------------------------------"

$TASKSET_CMD "$QEMU_BIN" \
    -machine q35 \
    "${CPU_ARGS[@]}" \
    -smp "$SMP" \
    -m "$MEM" \
    -kernel "$KERNEL" \
    -append "root=/dev/vda1 rw console=$CONSOLE nokaslr" \
    -drive file="$DISK_IMG",format=raw,if=virtio,cache=none,aio=native \
    -nographic \
    -no-reboot