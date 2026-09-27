#!/usr/bin/env bash
# scripts/build/build_control.sh - Compile baseline pristine upstream Linux v5.18-rc3
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ENV_DIR/scripts/common.sh"

KERNEL_DIR="${1:-${CONTROL_KERNEL_DIR:-$HOME/src/linux-pks-thesis-control}}"
OUTPUT_DIR="${OUTPUT_DIR:-$KERNEL_DIR/build_control}"
JOBS="${BUILD_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

[ -d "$KERNEL_DIR" ] || die "Kernel source directory not found: $KERNEL_DIR"
require_cmds make gcc bc flex bison

START_TIME=$(date +%s)

cd "$KERNEL_DIR"
mkdir -p "$OUTPUT_DIR"

make O="$OUTPUT_DIR" defconfig >/dev/null
make O="$OUTPUT_DIR" kvm_guest.config >/dev/null 2>&1 || true

# Storage, VirtIO & 9P virtfs
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_EXT4_FS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_VIRTIO_BLK
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_VIRTIO_PCI
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_VIRTIO_NET
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_NET_9P
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_NET_9P_VIRTIO
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_9P_FS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_9P_FS_POSIX_ACL

# Subsystems & Exploit prerequisites
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_USER_NS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_NET_NS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_XFRM
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_XFRM_USER
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_INET_ESP

# Crypto primitives
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_AES
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_CBC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_HMAC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_SHA256
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_AUTHENC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_USER_API
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_USER_API_AEAD
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_USER_API_SKCIPHER

# RxRPC fallback cipher paths
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_AF_RXRPC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_RXKAD
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_FCRYPT
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_PCBC

# Disable debug overhead for accurate baseline performance measurement
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_DEBUG_INFO
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_PROVE_LOCKING
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_KASAN

make O="$OUTPUT_DIR" olddefconfig >/dev/null
make O="$OUTPUT_DIR" -j"$JOBS" bzImage >/dev/null

BZIMAGE="$OUTPUT_DIR/arch/x86/boot/bzImage"
[ -f "$BZIMAGE" ] || die "Build finished but bzImage was not generated at $BZIMAGE"

ELAPSED=$(( $(date +%s) - START_TIME ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo "[build-control] Compiling Control Baseline Kernel ($BZIMAGE)... [DONE] (${MINS}m ${SECS}s)"
echo ""
