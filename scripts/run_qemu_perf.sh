#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# Performance Benchmark Launcher - Development Kernel (pcache_pks=on)
# Usage: ./run_qemu_perf.sh
#
# This script boots the mitigated kernel for the "implementation" run.
# The control baseline run is handled by run_qemu_control.sh.
#
# Memory handicap:
#   Control VM boots with mem=3840M (no pool reserved).
#   Mitigated VM boots with mem=4096M (kernel reserves 256M pool),
#   leaving 3840M usable, exactly matching the control environment.
# ----------------------------------------------------------------------

# User-configurable variables
DEV_KERNEL_DIR="${DEV_KERNEL_DIR:-$HOME/src/linux-pks-dev}"
DISK_IMG="${DISK_IMG:-$HOME/src/env/images/disk.img}"
SMP="${SMP:-4}"
CONSOLE="${CONSOLE:-ttyS0}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

# CPU pinning (optional, e.g., TASKSET_CPUS=4-7)
TASKSET_CPUS="${TASKSET_CPUS:-}"
if [ -n "$TASKSET_CPUS" ]; then
    TASKSET_CMD="taskset -c $TASKSET_CPUS"
else
    TASKSET_CMD=""
fi

# Total memory: 4G (kernel reserves 256M pool; usable remains 3840M)
TOTAL_MEM="${TOTAL_MEM:-4096M}"

KERNEL="$DEV_KERNEL_DIR/build_perf/arch/x86/boot/bzImage"
if [ ! -f "$KERNEL" ]; then
    echo "Error: Development kernel image not found at $KERNEL"
    echo "Run build_perf.sh first."
    exit 1
fi

if [ ! -f "$DISK_IMG" ]; then
    echo "Error: Disk image not found at $DISK_IMG"
    echo "Provision the disk image first."
    exit 1
fi

echo "-----------------------------------------------------"
echo " Performance Benchmark Boot (Mitigated Kernel)"
echo "   Kernel:      $KERNEL"
echo "   Disk:        $DISK_IMG"
echo "   PKS state:   on"
echo "   Total RAM:   $TOTAL_MEM"
echo "   CPU pinning: ${TASKSET_CPUS:-none}"
echo "-----------------------------------------------------"

$TASKSET_CMD "$QEMU_BIN" \
    -machine q35,accel=kvm \
    -cpu host \
    -smp "$SMP" \
    -m "$TOTAL_MEM" \
    -kernel "$KERNEL" \
    -append "root=/dev/vda rw console=$CONSOLE nokaslr pcache_pks=on" \
    -drive file="$DISK_IMG",format=raw,if=virtio,cache=none,aio=native \
    -nographic \
    -no-reboot