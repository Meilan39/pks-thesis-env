#!/usr/bin/env bash
# scripts/build/build_sec.sh - Compile security-hardened dev kernel with PKS diagnostics
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ENV_DIR/scripts/common.sh"

KERNEL_DIR="${1:-${DEV_KERNEL_DIR:-$HOME/src/linux-pks-thesis}}"
OUTPUT_DIR="${OUTPUT_DIR:-$KERNEL_DIR/build_sec}"
JOBS="${BUILD_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

[ -d "$KERNEL_DIR" ] || die "Kernel source directory not found: $KERNEL_DIR"
require_cmds make gcc bc flex bison

START_TIME=$(date +%s)
RAW_LOG="${RAW_LOG:-$ENV_DIR/results/raw/build-sec.log}"
mkdir -p "$(dirname "$RAW_LOG")"

echo "[build-sec] Compiling Security Kernel..."

cd "$KERNEL_DIR"
mkdir -p "$OUTPUT_DIR"

make O="$OUTPUT_DIR" defconfig > "$RAW_LOG" 2>&1
make O="$OUTPUT_DIR" kvm_guest.config >> "$RAW_LOG" 2>&1 || true

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
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_NET_KEY
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_INET_ESP
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_INET_ESPINTCP
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_INET6_ESP
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_INET6_ESPINTCP

# Crypto primitives
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_AES
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_CBC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_ECB
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_GCM
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_CTR
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

# PKS page-cache protection
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_PKS_TEST
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_PKS_TEST_ALL_KEYS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_PCACHE_PKS
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_PAGE_POISONING
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_DEBUG_PAGEALLOC
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_INIT_ON_ALLOC_DEFAULT_ON
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_INIT_ON_FREE_DEFAULT_ON
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_HIBERNATION

# Diagnostics, debugfs & fail-open handling
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_DEBUG_INFO
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_DEBUG_FS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_DYNAMIC_DEBUG
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_PCACHE_PKS_DEBUG
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_PANIC_ON_OOPS

make O="$OUTPUT_DIR" olddefconfig >> "$RAW_LOG" 2>&1
make O="$OUTPUT_DIR" -j"$JOBS" bzImage >> "$RAW_LOG" 2>&1

BZIMAGE="$OUTPUT_DIR/arch/x86/boot/bzImage"
[ -f "$BZIMAGE" ] || die "Build finished but bzImage was not generated at $BZIMAGE. Check $RAW_LOG"

ELAPSED=$(( $(date +%s) - START_TIME ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo "[build-sec] Compiling Security Kernel ($BZIMAGE)... [DONE] (${MINS}m ${SECS}s)"
echo ""
