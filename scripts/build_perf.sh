#!/usr/bin/env bash
# ==============================================================================
# scripts/build_perf.sh - Compile performance-optimized mitigated dev kernel
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

WORKSPACE_KERNEL="$(cd "$SCRIPT_DIR/../../linux-5.18-rc3" 2>/dev/null && pwd || true)"
KERNEL_DIR="${1:-${DEV_KERNEL_DIR:-${WORKSPACE_KERNEL:-$HOME/src/linux-pks-thesis}}}"
OUTPUT_DIR="$KERNEL_DIR/build_perf"

[ -d "$KERNEL_DIR" ] || die "Kernel source directory not found: $KERNEL_DIR"
require_cmds make gcc bc flex bison

log_header "Building Mitigated Performance Kernel (build_perf, dev)"
log_kv "Kernel Tree" "$KERNEL_DIR"
log_kv "Output Dir"  "$OUTPUT_DIR"
log_kv "Build Jobs"  "$(nproc)"

cd "$KERNEL_DIR"
mkdir -p "$OUTPUT_DIR"

log_step "Configuring baseline defconfig + kvm_guest"
make O="$OUTPUT_DIR" defconfig >/dev/null
make O="$OUTPUT_DIR" kvm_guest.config >/dev/null

log_step "Enabling storage and virtio drivers"
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_EXT4_FS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_VIRTIO_BLK
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_VIRTIO_PCI

log_step "Enabling exploit prerequisite subsystems"
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_USER_NS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_NET_NS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_XFRM
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_XFRM_USER
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_INET_ESP

log_step "Enabling crypto primitives"
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_AES
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_CBC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_HMAC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_SHA256
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_AUTHENC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_USER_API
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_USER_API_AEAD
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_USER_API_SKCIPHER

log_step "Enabling RxRPC fallback cipher paths"
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_AF_RXRPC
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_RXKAD
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_FCRYPT
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_CRYPTO_PCBC

log_step "Configuring PKS page-cache protection"
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_PKS_TEST
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_PKS_TEST_ALL_KEYS
scripts/config --file "$OUTPUT_DIR"/.config --enable CONFIG_PCACHE_PKS
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_PAGE_POISONING
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_DEBUG_PAGEALLOC
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_INIT_ON_ALLOC_DEFAULT_ON
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_INIT_ON_FREE_DEFAULT_ON
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_HIBERNATION

log_step "Disabling debug overhead for performance measurement"
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_DEBUG_INFO
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_PROVE_LOCKING
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_KASAN

log_step "Finalizing configuration and compiling bzImage"
make O="$OUTPUT_DIR" olddefconfig >/dev/null
make O="$OUTPUT_DIR" -j"$(nproc)"

BZIMAGE="$OUTPUT_DIR/arch/x86/boot/bzImage"
if [ -f "$BZIMAGE" ]; then
    log_ok "Mitigated performance kernel build complete: $BZIMAGE"
else
    die "Build finished but bzImage was not generated at $BZIMAGE"
fi