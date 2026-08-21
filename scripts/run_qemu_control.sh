#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# Performance Benchmark Launcher - Control Kernel
# Usage: ./run_qemu_control.sh
# ----------------------------------------------------------------------

# User-configurable variables
CONTROL_KERNEL_DIR="${CONTROL_KERNEL_DIR:-$HOME/src/linux-control}"
DISK_IMG="${DISK_IMG:-$HOME/src/env/images/disk.img}"
SMP="${SMP:-4}"
CONSOLE="${CONSOLE:-ttyS0}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

# CPU pinning (optional)
TASKSET_CPUS="${TASKSET_CPUS:-}"
if [ -n "$TASKSET_CPUS" ]; then
    TASKSET_CMD="taskset -c $TASKSET_CPUS"
else
    TASKSET_CMD=""
fi

# Memory handicap: control VM gets 3840M to match the dev VM's usable memory
# (4G total with 256M reserved for the static pool)
MEM="${MEM:-3840M}"

KERNEL="$CONTROL_KERNEL_DIR/build_perf/arch/x86/boot/bzImage"
if [ ! -f "$KERNEL" ]; then
    echo "Error: Control kernel image not found at $KERNEL"
    echo "Run build_control.sh first."
    exit 1
fi

if [ ! -f "$DISK_IMG" ]; then
    echo "Error: Disk image not found at $DISK_IMG"
    exit 1
fi

echo "-----------------------------------------------------"
echo " Performance Benchmark Boot (Control Kernel)"
echo "   Kernel:      $KERNEL"
echo "   Disk:        $DISK_IMG"
echo "   Total RAM:   $MEM"
echo "   CPU pinning: ${TASKSET_CPUS:-none}"
echo "-----------------------------------------------------"

$TASKSET_CMD "$QEMU_BIN" \
    -machine q35,accel=kvm \
    -cpu host \
    -smp "$SMP" \
    -m "$MEM" \
    -kernel "$KERNEL" \
    -append "root=/dev/vda rw console=$CONSOLE nokaslr" \
    -drive file="$DISK_IMG",format=raw,if=virtio,cache=none,aio=native \
    -nographic \
    -no-reboot