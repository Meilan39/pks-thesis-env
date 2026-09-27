#!/usr/bin/env bash
# scripts/build/build_control.sh - Compile baseline pristine upstream Linux v5.18-rc3
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ENV_DIR/scripts/common.sh"
-include "$ENV_DIR/config.mk" 2>/dev/null || true

KERNEL_DIR="${CONTROL_KERNEL_DIR:-$ENV_DIR/../linux-5.18-rc3}"
OUTPUT_DIR="${OUTPUT_DIR:-$ENV_DIR/build_control}"
JOBS="${BUILD_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 8)}"

[ -d "$KERNEL_DIR" ] || die "Kernel source directory not found: $KERNEL_DIR"
mkdir -p "$OUTPUT_DIR"

START_TIME=$(date +%s)

cd "$KERNEL_DIR"
make O="$OUTPUT_DIR" defconfig >/dev/null
make O="$OUTPUT_DIR" kvm_guest.config >/dev/null 2>&1 || true

# Storage & VirtIO
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_EXT4_FS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_VIRTIO_BLK
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_VIRTIO_PCI
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_VIRTIO_NET
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_NET_9P
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_NET_9P_VIRTIO
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_9P_FS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_9P_FS_POSIX_ACL

make O="$OUTPUT_DIR" -j"$JOBS" bzImage >/dev/null

ELAPSED=$(( $(date +%s) - START_TIME ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo "[build-control] Compiling Control Baseline Kernel (arch/x86/boot/bzImage)... [DONE] (${MINS}m ${SECS}s)"
echo ""
