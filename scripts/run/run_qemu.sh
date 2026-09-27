#!/usr/bin/env bash
# scripts/run/run_qemu.sh - Core QEMU virtualization runner
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ENV_DIR/scripts/common.sh"

KERNEL_VARIANT="${1:-${KERNEL_VARIANT:-perf}}"
PKS_MODE="${2:-${PKS_MODE:-on}}"
AUTO_TARGET="${3:-${AUTO_TARGET:-shell}}"
LOG_FILE="${4:-}"

DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
KERNEL_IMG="${KERNEL_IMG:-$ENV_DIR/build_${KERNEL_VARIANT}/arch/x86/boot/bzImage}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
SMP="${SMP:-4}"
MEM="${MEM:-4096}"

[ -f "$KERNEL_IMG" ] || die "Kernel image not found: $KERNEL_IMG. Run 'make build-${KERNEL_VARIANT}' first."
[ -f "$DISK_IMG" ] || die "Disk image not found: $DISK_IMG. Run 'make disk-provision' first."

# Construct kernel command line
CMDLINE="root=/dev/vda1 rw console=ttyS0 quiet nokaslr"
if [ "$KERNEL_VARIANT" = "control" ]; then
    CMDLINE="$CMDLINE pcache_control=1"
elif [ "$PKS_MODE" = "on" ]; then
    CMDLINE="$CMDLINE pcache_pks=on"
else
    CMDLINE="$CMDLINE pcache_pks=off"
fi

# Acceleration flags
ACCEL_ARGS=("-cpu" "qemu64,+pks" "-accel" "tcg")
if [ -e /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL_ARGS=("-cpu" "host" "-enable-kvm")
fi

# 9p workspace share
VIRTFS_ARGS=("-virtfs" "local,path=${ENV_DIR},mount_tag=pks_env,security_model=none")

if [ "$AUTO_TARGET" != "shell" ] && [ -n "$AUTO_TARGET" ]; then
    CMDLINE="$CMDLINE pks_auto=${AUTO_TARGET} panic=-1"
    
    QEMU_CMD=(
        "$QEMU_BIN"
        -m "${MEM}M"
        -smp "$SMP"
        "${ACCEL_ARGS[@]}"
        -kernel "$KERNEL_IMG"
        -drive "file=${DISK_IMG},format=raw,if=virtio"
        "${VIRTFS_ARGS[@]}"
        -nographic
        -monitor none
        -serial stdio
        -no-reboot
        -append "$CMDLINE"
    )
    
    TIMEOUT_CMD=()
    if command -v timeout >/dev/null 2>&1; then
        TIMEOUT_CMD=("timeout" "--kill-after=10s" "300s")
    fi
    
    if [ -n "$LOG_FILE" ]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        "${TIMEOUT_CMD[@]}" "${QEMU_CMD[@]}" > "$LOG_FILE" 2>&1 || true
    else
        "${TIMEOUT_CMD[@]}" "${QEMU_CMD[@]}" 2>&1 || true
    fi
else
    echo "[run-qemu] Launching interactive serial console (Kernel: ${KERNEL_VARIANT}, Mitigation: ${PKS_MODE})..."
    echo "[run-qemu] Press 'Ctrl-A X' to terminate the QEMU instance."
    echo ""
    exec "$QEMU_BIN" \
        -m "${MEM}M" \
        -smp "$SMP" \
        "${ACCEL_ARGS[@]}" \
        -kernel "$KERNEL_IMG" \
        -drive "file=${DISK_IMG},format=raw,if=virtio" \
        "${VIRTFS_ARGS[@]}" \
        -nographic \
        -serial mon:stdio \
        -append "$CMDLINE"
fi
