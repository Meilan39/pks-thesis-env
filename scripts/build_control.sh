#!/usr/bin/env bash
# ==============================================================================
# scripts/build_control.sh - Compile baseline upstream control kernel
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CANDIDATES=(
    "${1:-}"
    "${CONTROL_KERNEL_DIR:-}"
    "$(cd "$SCRIPT_DIR/../../linux-pks-thesis-control" 2>/dev/null && pwd || true)"
    "$(cd "$SCRIPT_DIR/../../linux-control" 2>/dev/null && pwd || true)"
    "$HOME/src/linux-pks-thesis-control"
    "$HOME/src/linux-control"
)

KERNEL_DIR=""
for cand in "${CANDIDATES[@]}"; do
    if [ -n "$cand" ] && [ -d "$cand" ]; then
        KERNEL_DIR="$cand"
        break
    fi
done

KERNEL_DIR="${KERNEL_DIR:-${1:-${CONTROL_KERNEL_DIR:-$HOME/src/linux-pks-thesis-control}}}"
OUTPUT_DIR="${OUTPUT_DIR:-$KERNEL_DIR/build_perf}"

[ -d "$KERNEL_DIR" ] || die "Control kernel source directory not found: $KERNEL_DIR"
require_cmds make gcc bc flex bison

log_header "Building Control Baseline Kernel (build_perf, control)"
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

log_step "Disabling debug overhead for performance measurement"
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_DEBUG_INFO
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_PROVE_LOCKING
scripts/config --file "$OUTPUT_DIR"/.config --disable CONFIG_KASAN

log_step "Finalizing configuration and compiling bzImage"
make O="$OUTPUT_DIR" olddefconfig >/dev/null
make O="$OUTPUT_DIR" -j"$(nproc)"

BZIMAGE="$OUTPUT_DIR/arch/x86/boot/bzImage"
if [ -f "$BZIMAGE" ]; then
    log_ok "Control kernel build complete: $BZIMAGE"
else
    die "Build finished but bzImage was not generated at $BZIMAGE"
fi