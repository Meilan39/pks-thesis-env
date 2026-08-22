#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# Security Validation Launcher (flexible CPU mode)
# Usage: ./run_qemu_sec.sh [off|on]
#   off  -> boot with pcache_pks=off (vulnerable state)
#   on   -> boot with pcache_pks=on  (mitigated state)
#
# The script attempts to use KVM with -cpu host if the host supports PKS.
# If not, it falls back to TCG with -cpu max,pks=on and prints a warning.
# ----------------------------------------------------------------------

# User-configurable variables
DEV_KERNEL_DIR="${DEV_KERNEL_DIR:-$HOME/src/linux-pks-thesis}"
DISK_IMG="${DISK_IMG:-$HOME/src/env/images/disk.img}"
MEM="${MEM:-4G}"
SMP="${SMP:-4}"
CONSOLE="${CONSOLE:-ttyS0}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

# Parse argument
if [ $# -ne 1 ] || [[ "$1" != "off" && "$1" != "on" ]]; then
    echo "Usage: $0 [off|on]"
    exit 1
fi
PKS_STATE="$1"

KERNEL="$DEV_KERNEL_DIR/build_sec/arch/x86/boot/bzImage"
[ -f "$KERNEL" ] || { echo "Error: Kernel not found at $KERNEL. Run build_sec.sh first."; exit 1; }
[ -f "$DISK_IMG" ] || { echo "Error: Disk image not found at $DISK_IMG. Provision it first."; exit 1; }

# Determine CPU mode
CPU_ARGS=()
MODE=""
if [ -e /dev/kvm ] && grep -qw pks /proc/cpuinfo; then
    MODE="KVM / host"
    CPU_ARGS=(-enable-kvm -cpu host)
elif [ -e /dev/kvm ]; then
    MODE="KVM / host (host lacks PKS, falling back to TCG)"
    CPU_ARGS=(-cpu max,pks=on)
    echo "WARNING: Host CPU does not expose supervisor PKS."
    echo "         Falling back to TCG emulation. Security validation results will be INVALID."
    echo "         For meaningful results, use a host with supervisor PKS."
else
    MODE="TCG / max,pks=on"
    CPU_ARGS=(-cpu max,pks=on)
    echo "WARNING: KVM not available, using TCG emulation."
    echo "         Security validation results will be INVALID."
fi

echo "-----------------------------------------------------"
echo " Security Validation Boot"
echo "   Kernel:    $KERNEL"
echo "   Disk:      $DISK_IMG"
echo "   PKS state: $PKS_STATE"
echo "   CPU mode:  $MODE"
echo "-----------------------------------------------------"

"$QEMU_BIN" \
    -machine q35 \
    "${CPU_ARGS[@]}" \
    -smp "$SMP" \
    -m "$MEM" \
    -kernel "$KERNEL" \
    -append "root=/dev/vda1 rw console=$CONSOLE nokaslr pcache_pks=$PKS_STATE" \
    -drive file="$DISK_IMG",format=raw,if=virtio,cache=none,aio=native \
    -nographic \
    -no-reboot