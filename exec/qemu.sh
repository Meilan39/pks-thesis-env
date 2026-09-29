#!/usr/bin/env bash
# exec/qemu.sh - QEMU substrate adapter implementing the executor contract:
#
#     exec/qemu.sh <kernel_variant> <pks_mode> <target> [transcript_out]
#
#   kernel_variant : control | sec | perf   (selects the bzImage)
#   pks_mode       : on | off                (pcache_pks=; ignored for control)
#   target         : shell                   -> interactive serial console, OR
#                    test | sec | perf       -> in-guest axis (all leaves), OR
#                    <axis>/<leaf>           -> one in-guest leaf (e.g. sec/copy-fail)
#   transcript_out : host path for the raw serial transcript (headless only)
#
# It boots headless, streams serial live to the transcript (panic-safe), and
# returns. It NEVER fabricates output: if prerequisites are missing it fails.
set -euo pipefail

ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ENV_DIR/common.sh"

KVAR="${1:-perf}"; MODE="${2:-on}"; TARGET="${3:-shell}"; TRANSCRIPT="${4:-}"

DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
DEV_KERNEL_DIR="${DEV_KERNEL_DIR:-$HOME/src/linux-pks-thesis}"
CONTROL_KERNEL_DIR="${CONTROL_KERNEL_DIR:-$HOME/src/linux-pks-thesis-control}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
SMP="${SMP:-4}"; MEM="${MEM:-4096}"; BATCH_TIMEOUT_SEC="${BATCH_TIMEOUT_SEC:-300}"

# Resolve the kernel image for the requested variant.
if [ "$KVAR" = "control" ]; then
    KERNEL_IMG="${KERNEL_IMG:-$CONTROL_KERNEL_DIR/build_control/arch/x86/boot/bzImage}"
else
    KERNEL_IMG="${KERNEL_IMG:-$DEV_KERNEL_DIR/build_${KVAR}/arch/x86/boot/bzImage}"
fi

[ -f "$KERNEL_IMG" ] || die "Kernel image not found: $KERNEL_IMG (run 'make build' first)."
[ -f "$DISK_IMG" ]   || die "Disk image not found: $DISK_IMG (run 'make disk' first)."
command -v "$QEMU_BIN" >/dev/null 2>&1 || die "$QEMU_BIN not found."

# Accelerator: real KVM when usable, else TCG with emulated PKS.
ACCEL=("-cpu" "max,vendor=GenuineIntel,pks=on" "-accel" "tcg")
if [ -e /dev/kvm ] && [ -w /dev/kvm ] && grep -qw pks /proc/cpuinfo 2>/dev/null; then
    ACCEL=("-cpu" "host" "-enable-kvm")
fi
VIRTFS=("-virtfs" "local,path=${ENV_DIR},mount_tag=pks_env,security_model=none")

# Kernel command line. Panic is the intended fail-closed outcome for sec, so we
# keep panic=1 + -no-reboot: the VM halts and QEMU exits, transcript preserved.
CMDLINE="root=/dev/vda1 rw console=ttyS0 nokaslr"
if [ "$KVAR" = "control" ]; then CMDLINE="$CMDLINE pcache_control=1"; else CMDLINE="$CMDLINE pcache_pks=${MODE}"; fi

COMMON_ARGS=(-machine q35 -m "${MEM}M" -smp "$SMP" "${ACCEL[@]}"
             -kernel "$KERNEL_IMG" -drive "file=${DISK_IMG},format=raw,if=virtio"
             "${VIRTFS[@]}" -net none -nographic)

# Interactive debugging console.
if [ "$TARGET" = "shell" ]; then
    log_info "Interactive console (kernel=$KVAR mode=$MODE). Ctrl-A X to quit."
    exec "$QEMU_BIN" "${COMMON_ARGS[@]}" -serial mon:stdio -append "$CMDLINE quiet"
fi

# Headless automated run.
[ -n "$TRANSCRIPT" ] || die "headless run requires a transcript path (arg 4)."
mkdir -p "$(dirname "$TRANSCRIPT")"
CMDLINE="$CMDLINE pks_run=${TARGET} pks_auto=${TARGET} panic=1 systemd.mask=serial-getty@ttyS0.service"

TIMEOUT=(); command -v timeout >/dev/null 2>&1 && TIMEOUT=(timeout --kill-after=10s "${BATCH_TIMEOUT_SEC}s")

log_info "[exec/qemu] boot kernel=$KVAR mode=$MODE target=$TARGET -> $(basename "$TRANSCRIPT")"
"${TIMEOUT[@]}" "$QEMU_BIN" "${COMMON_ARGS[@]}" -no-reboot -serial stdio -monitor none \
    -append "$CMDLINE" > "$TRANSCRIPT" 2>&1 || true

if ! grep -q '^STATUS ' "$TRANSCRIPT" 2>/dev/null; then
    sz=$(wc -c < "$TRANSCRIPT" 2>/dev/null || echo 0)
    log_warn "[exec/qemu] no STATUS lines in transcript (${sz} bytes: $(basename "$TRANSCRIPT"))."
    if [ "$sz" -lt 200 ]; then
        log_warn "[exec/qemu] transcript nearly empty -> QEMU likely failed to start. Contents:"
        sed 's/^/    | /' "$TRANSCRIPT" >&2
    else
        log_warn "[exec/qemu] guest booted but emitted no result. Last 20 transcript lines:"
        tail -n 20 "$TRANSCRIPT" | sed 's/^/    | /' >&2
    fi
fi
