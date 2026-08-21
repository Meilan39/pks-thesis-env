#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# Security Validation Launcher
# Usage: ./run_qemu_sec.sh [off|on]
#   off  -> boot with pcache_pks=off (vulnerable state)
#   on   -> boot with pcache_pks=on  (mitigated state)
# ----------------------------------------------------------------------

# User-configurable variables
DEV_KERNEL_DIR="${DEV_KERNEL_DIR:-$HOME/src/linux-pks-dev}"   # dev tree with PKS patches
DISK_IMG="${DISK_IMG:-$HOME/src/env/images/disk.img}"        # persistent root filesystem
MEM="${MEM:-4G}"                                             # total VM memory (handicap handled separately if needed)
SMP="${SMP:-4}"
CONSOLE="${CONSOLE:-ttyS0}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

# Parse argument
if [ $# -ne 1 ] || [[ "$1" != "off" && "$1" != "on" ]]; then
    echo "Usage: $0 [off|on]"
    exit 1
fi
PKS_STATE="$1"

# Check dependencies
if ! command -v "$QEMU_BIN" &>/dev/null; then
    echo "Error: $QEMU_BIN not found. Install qemu-system-x86."
    exit 1
fi

if ! grep -qw pks /proc/cpuinfo; then
    echo "ERROR: Host CPU does not expose supervisor PKS. Security validation requires hardware PKS."
    echo "       Exiting to avoid invalid results."
    exit 1
fi

KERNEL="$DEV_KERNEL_DIR/build_sec/arch/x86/boot/bzImage"
if [ ! -f "$KERNEL" ]; then
    echo "Error: Kernel image not found at $KERNEL"
    echo "Run build_sec.sh first."
    exit 1
fi

if [ ! -f "$DISK_IMG" ]; then
    echo "Error: Disk image not found at $DISK_IMG"
    echo "Provision the disk image first."
    exit 1
fi

echo "-----------------------------------------------------"
echo " Security Validation Boot"
echo "   Kernel:    $KERNEL"
echo "   Disk:      $DISK_IMG"
echo "   PKS state: $PKS_STATE"
echo "   CPU mode:  KVM / host"
echo "-----------------------------------------------------"

# Launch QEMU with -enable-kvm -cpu host
"$QEMU_BIN" \
    -machine q35,accel=kvm \
    -cpu host \
    -smp "$SMP" \
    -m "$MEM" \
    -kernel "$KERNEL" \
    -append "root=/dev/vda rw console=$CONSOLE nokaslr pcache_pks=$PKS_STATE" \
    -drive file="$DISK_IMG",format=raw,if=virtio,cache=none,aio=native \
    -nographic \
    -no-reboot