#!/usr/bin/env bash
set -euo pipefail

KERNEL_DIR="${1:-$HOME/src/linux-pks-dev}"
OUTPUT_DIR="$KERNEL_DIR/build_perf"

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

# Disable debug overhead
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_DEBUG_INFO
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_PROVE_LOCKING
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_KASAN

make O="$OUTPUT_DIR" olddefconfig
make O="$OUTPUT_DIR" -j"$(nproc)"