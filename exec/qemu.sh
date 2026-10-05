#!/usr/bin/env bash
# exec/qemu.sh - QEMU substrate adapter implementing the executor contract:
#
#     exec/qemu.sh <kernel_variant> <pks_mode> <target> [transcript_out]
#
# Parameters:
#   kernel_variant : control | sec | perf (selects the bzImage)
#   pks_mode       : on | off (pcache_pks=; ignored for control)
#   target         : shell             -> interactive serial console, OR
#                    test | sec | perf -> in-guest axis (all leaves), OR
#                    <axis>/<leaf>     -> one in-guest leaf (e.g. sec/copy-fail)
#   transcript_out : host path for the raw serial transcript (headless execution only)
#
# Boots headless, streams serial output live to the transcript file, and returns.
# Never fabricates output; fails fast if required artifacts are missing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

# ==============================================================================
# 1. Parameter Parsing and Default Configuration
# ==============================================================================
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
BATCH_TIMEOUT_SEC="${BATCH_TIMEOUT_SEC:-300}"

# ==============================================================================
# 2. Kernel & Artifact Validation
# ==============================================================================
if [ "$KERNEL_VARIANT" = "control" ]; then
    KERNEL_IMG="${KERNEL_IMG:-$CONTROL_KERNEL_DIR/build_control/arch/x86/boot/bzImage}"
else
    KERNEL_IMG="${KERNEL_IMG:-$DEV_KERNEL_DIR/build_${KERNEL_VARIANT}/arch/x86/boot/bzImage}"
fi

[ -f "$KERNEL_IMG" ] || die "Kernel image not found: $KERNEL_IMG (run 'make build' first)."
[ -f "$DISK_IMG" ]   || die "Disk image not found: $DISK_IMG (run 'make disk' first)."
command -v "$QEMU_BIN" >/dev/null 2>&1 || die "$QEMU_BIN not found."

# ==============================================================================
# 3. CPU Accelerator and Filesystem Virtualization
# ==============================================================================
# Emulated TCG CPU configuration with PKS capability
ACCEL=("-cpu" "max,pks=on" "-accel" "tcg")

# If real KVM with hardware PKS is available on the host, utilize host passthrough
if [ -e /dev/kvm ] && [ -w /dev/kvm ] && grep -qw pks /proc/cpuinfo 2>/dev/null; then
    ACCEL=("-cpu" "host" "-enable-kvm")
fi

VIRTFS=("-virtfs" "local,path=${REPO_ROOT},mount_tag=pks_env,security_model=none")

# ==============================================================================
# 4. Kernel Command-Line Formulation
# ==============================================================================
# Panic is the expected fail-closed behavior for security tests, so panic=1 and
# -no-reboot ensure the VM halts cleanly and exits QEMU with transcript intact.
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

# ==============================================================================
# 5. Interactive Console Mode
# ==============================================================================
if [ "$TARGET" = "shell" ]; then
    log_info "Interactive console (kernel=$KERNEL_VARIANT mode=$PKS_MODE). Press Ctrl-A X to exit."
    exec "$QEMU_BIN" "${COMMON_ARGS[@]}" -nographic -serial mon:stdio -append "$CMDLINE quiet"
fi

# ==============================================================================
# 6. Headless Execution & Serial Capture
# ==============================================================================
if [ -z "$TRANSCRIPT_PATH" ]; then
    die "Headless run requires a transcript path (argument 4)."
fi

mkdir -p "$(dirname "$TRANSCRIPT_PATH")"
CMDLINE="$CMDLINE pks_run=${TARGET} pks_auto=${TARGET} panic=1 systemd.mask=serial-getty@ttyS0.service"

TIMEOUT=()
if command -v timeout >/dev/null 2>&1; then
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

# Record command line for offline reproduction
{
    printf '### exec/qemu argv:\n'
    printf '%q ' "${QEMU_ARGV[@]}"
    printf '\n\n'
} > "$TRANSCRIPT_PATH"

start_time=$(date +%s)

# Execute QEMU without allowing nonzero exit code to trigger set -e prematurely
if "${TIMEOUT[@]}" "${QEMU_ARGV[@]}" </dev/null >> "$TRANSCRIPT_PATH" 2>&1; then
    qemu_rc=0
else
    qemu_rc=$?
fi

elapsed_secs=$(( $(date +%s) - start_time ))
echo "### exec/qemu exit=$qemu_rc elapsed=${elapsed_secs}s" >> "$TRANSCRIPT_PATH"

# ==============================================================================
# 7. Diagnostic Validation
# ==============================================================================
if ! grep -q '^STATUS ' "$TRANSCRIPT_PATH" 2>/dev/null; then
    guest_bytes=$(grep -vE '^### ' "$TRANSCRIPT_PATH" | wc -c | tr -d ' ')
    log_warn "[exec/qemu] no STATUS (exit=$qemu_rc elapsed=${elapsed_secs}s, ${guest_bytes} bytes of guest output)."

    case "$qemu_rc" in
        124|137)
            log_warn "[exec/qemu] QEMU hit the ${BATCH_TIMEOUT_SEC}s timeout -> serial output stalled or guest hung."
            ;;
        0)
            if [ "$guest_bytes" -eq 0 ]; then
                log_warn "[exec/qemu] QEMU exited 0 with no output -> guest failed to initialize."
            fi
            ;;
        *)
            log_warn "[exec/qemu] QEMU exited $qemu_rc before/at startup -> check arguments and environment."
            ;;
    esac

    log_warn "[exec/qemu] full transcript ($(basename "$TRANSCRIPT_PATH")):"
    sed 's/^/    | /' "$TRANSCRIPT_PATH" >&2
fi

