#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_KERNEL="$(cd "$SCRIPT_DIR/../../linux-5.18-rc3" 2>/dev/null && pwd || true)"
KERNEL_DIR="${1:-${DEV_KERNEL_DIR:-${WORKSPACE_KERNEL:-$HOME/src/linux-pks-dev}}}"
OUTPUT_DIR="$KERNEL_DIR/build_sec"

cd "$KERNEL_DIR"
make O="$OUTPUT_DIR" defconfig
make O="$OUTPUT_DIR" kvm_guest.config

# Storage / filesystem
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_EXT4_FS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_VIRTIO_BLK
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_VIRTIO_PCI

# Exploit dependencies
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_USER_NS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_NET_NS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_XFRM
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_XFRM_USER
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_INET_ESP

# Crypto
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_AES
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_CBC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_HMAC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_SHA256
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_AUTHENC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_USER_API
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_USER_API_AEAD
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_USER_API_SKCIPHER

# Dirty Frag RxRPC fallback
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_AF_RXRPC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_RXKAD
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_FCRYPT
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_PCBC

# PKS Subsystem & Page-Cache Protection
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_PKS_TEST
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_PKS_TEST_ALL_KEYS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_PCACHE_PKS
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_PAGE_POISONING
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_DEBUG_PAGEALLOC
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_INIT_ON_ALLOC_DEFAULT_ON
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_INIT_ON_FREE_DEFAULT_ON
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_HIBERNATION

# Enable debug features for security validation
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_DEBUG_INFO
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_PANIC_ON_OOPS

make O="$OUTPUT_DIR" olddefconfig
make O="$OUTPUT_DIR" -j"$(nproc)"