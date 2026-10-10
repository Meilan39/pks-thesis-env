#!/usr/bin/env bash
# ==============================================================================
# exec/qemu.sh - QEMU substrate adapter (executor contract)
# ==============================================================================
#     exec/qemu.sh <kernel_variant> <pks_mode> <target> [transcript_out]
#
#   kernel_variant : control | sec | perf (selects the bzImage)
#   pks_mode       : on | off (pcache_pks=; ignored for control)
#   target         : shell             -> interactive serial console, OR
#                    test | sec | perf -> in-guest axis (all leaves), OR
#                    <axis>/<leaf>     -> one in-guest leaf (e.g. sec/copy-fail)
#   transcript_out : host path for the raw serial transcript (headless only)
#
# Boots headless, streams serial output live to the transcript, and returns.
# Never fabricates output; fails fast if required artifacts are missing.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

# ------------------------------------------------------------------------------
# Parameters & defaults
# ------------------------------------------------------------------------------
KERNEL_VARIANT="${1:-perf}"
PKS_MODE="${2:-on}"
TARGET="${3:-shell}"
TRANSCRIPT_PATH="${4:-}"

DISK_IMG="${DISK_IMG:-$REPO_ROOT/images/disk.img}"
DEV_KERNEL_DIR="${DEV_KERNEL_DIR:-$HOME/src/linux-pks-thesis}"
CONTROL_KERNEL_DIR="${CONTROL_KERNEL_DIR:-$HOME/src/linux-pks-thesis-control}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

SMP="${SMP:-4}"
MEM="${MEM:-4096}"
BATCH_TIMEOUT_SEC="${BATCH_TIMEOUT_SEC:-0}"

# ------------------------------------------------------------------------------
# Kernel & artifact validation
# ------------------------------------------------------------------------------
if [ "$KERNEL_VARIANT" = "control" ]; then
    KERNEL_IMG="${KERNEL_IMG:-$CONTROL_KERNEL_DIR/build_control/arch/x86/boot/bzImage}"
else
    KERNEL_IMG="${KERNEL_IMG:-$DEV_KERNEL_DIR/build_${KERNEL_VARIANT}/arch/x86/boot/bzImage}"
fi

[ -f "$KERNEL_IMG" ] || die "Kernel image not found: $KERNEL_IMG (run 'make build' first)."
[ -f "$DISK_IMG" ]   || die "Disk image not found: $DISK_IMG (run 'make disk' first)."
command -v "$QEMU_BIN" >/dev/null 2>&1 || die "$QEMU_BIN not found."

# ------------------------------------------------------------------------------
# CPU accelerator & filesystem virtualization
# ------------------------------------------------------------------------------
# Emulated TCG CPU with PKS capability.
ACCEL=("-cpu" "max,pks=on" "-accel" "tcg")

# Prefer host passthrough when real KVM with hardware PKS is available.
if [ -e /dev/kvm ] && [ -w /dev/kvm ] && grep -qw pks /proc/cpuinfo 2>/dev/null; then
    ACCEL=("-cpu" "host" "-enable-kvm")
fi

VIRTFS=("-virtfs" "local,path=${REPO_ROOT},mount_tag=pks_env,security_model=none")

# ------------------------------------------------------------------------------
# Kernel command line
# ------------------------------------------------------------------------------
# Panic is the expected fail-closed behavior for security tests, so panic=1 plus
# -no-reboot halt the VM cleanly and exit QEMU with the transcript intact.
CMDLINE="root=/dev/vda1 rw console=ttyS0 nokaslr"
if [ "$KERNEL_VARIANT" = "control" ]; then
    CMDLINE="$CMDLINE pcache_control=1"
else
    CMDLINE="$CMDLINE pcache_pks=${PKS_MODE}"
fi

COMMON_ARGS=(
    -machine q35
    -m "${MEM}M"
    -smp "$SMP"
    "${ACCEL[@]}"
    -kernel "$KERNEL_IMG"
    -drive "file=${DISK_IMG},format=raw,if=virtio"
    "${VIRTFS[@]}"
)

# ------------------------------------------------------------------------------
# Interactive console mode
# ------------------------------------------------------------------------------
if [ "$TARGET" = "shell" ]; then
    log_info "Interactive console (kernel=$KERNEL_VARIANT mode=$PKS_MODE). Press Ctrl-A X to exit."
    exec "$QEMU_BIN" "${COMMON_ARGS[@]}" -nographic -serial mon:stdio -append "$CMDLINE quiet"
fi

# ------------------------------------------------------------------------------
# Headless execution & serial capture
# ------------------------------------------------------------------------------
if [ -z "$TRANSCRIPT_PATH" ]; then
    die "Headless run requires a transcript path (argument 4)."
fi

mkdir -p "$(dirname "$TRANSCRIPT_PATH")"
# SYSTEMD_COLORS=0 reaches PID 1 via init's environment (the kernel forwards
# unrecognized name=value cmdline tokens there), stripping systemd's boot color
# from the transcript. Headless only; the interactive `shell` path keeps color.
CMDLINE="$CMDLINE pks_run=${TARGET} pks_auto=${TARGET} panic=1 systemd.mask=serial-getty@ttyS0.service SYSTEMD_COLORS=0"

TIMEOUT=()
if [ -n "${BATCH_TIMEOUT_SEC:-}" ] && [ "$BATCH_TIMEOUT_SEC" -gt 0 ] 2>/dev/null && command -v timeout >/dev/null 2>&1; then
    TIMEOUT=(timeout --kill-after=10s "${BATCH_TIMEOUT_SEC}s")
fi

log_info "[exec/qemu] boot kernel=$KERNEL_VARIANT mode=$PKS_MODE target=$TARGET -> $(basename "$TRANSCRIPT_PATH")"

QEMU_ARGV=(
    "$QEMU_BIN"
    "${COMMON_ARGS[@]}"
    -display none
    -serial stdio
    -monitor none
    -no-reboot
    -append "$CMDLINE"
)

# Record the command line for offline reproduction.
{
    printf '### exec/qemu argv:\n'
    printf '%q ' "${QEMU_ARGV[@]}"
    printf '\n\n'
} > "$TRANSCRIPT_PATH"

start_time=$(date +%s)

# Run QEMU without letting a nonzero exit trip set -e prematurely.
if "${TIMEOUT[@]}" "${QEMU_ARGV[@]}" </dev/null >> "$TRANSCRIPT_PATH" 2>&1; then
    qemu_rc=0
else
    qemu_rc=$?
fi

elapsed_secs=$(( $(date +%s) - start_time ))
echo "### exec/qemu exit=$qemu_rc elapsed=${elapsed_secs}s" >> "$TRANSCRIPT_PATH"

# ------------------------------------------------------------------------------
# Diagnostic validation
# ------------------------------------------------------------------------------
# The transcript is saved verbatim at TRANSCRIPT_PATH and never echoed (echoing
# it is what bled every boot into the axis logs). Flag a run -- one line, no dump
# -- only on real trouble: QEMU failed (timeout / abnormal exit) or the guest
# emitted nothing. Expected fail-closed panics exit 0 with output and stay
# silent; the axis runner resolves the verdict from the transcript.
guest_bytes=$({ grep -vE '^### ' "$TRANSCRIPT_PATH" 2>/dev/null || true; } | wc -c | tr -d ' ')
if [ "$qemu_rc" -ne 0 ] || [ "$guest_bytes" -eq 0 ]; then
    log_warn "[exec/qemu] run suspect: exit=$qemu_rc elapsed=${elapsed_secs}s guest_bytes=$guest_bytes; see $TRANSCRIPT_PATH"
fi
