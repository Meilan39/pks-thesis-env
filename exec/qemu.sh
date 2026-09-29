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

# Accelerator. This host has no /dev/kvm, so TCG (which emulates PKS) is the
# path. `-cpu max,pks=on` is the exact spec proven to boot here; do NOT add
# vendor=GenuineIntel (it makes QEMU 6.2 fail to bring up the guest). Real KVM
# is used only when the host CPU actually has PKS, so enforcement stays genuine.
ACCEL=("-cpu" "max,pks=on" "-accel" "tcg")
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
             "${VIRTFS[@]}")

# Interactive debugging console: -nographic muxes serial+monitor onto the tty.
if [ "$TARGET" = "shell" ]; then
    log_info "Interactive console (kernel=$KVAR mode=$MODE). Ctrl-A X to quit."
    exec "$QEMU_BIN" "${COMMON_ARGS[@]}" -nographic -serial mon:stdio -append "$CMDLINE quiet"
fi

# Headless automated run.
[ -n "$TRANSCRIPT" ] || die "headless run requires a transcript path (arg 4)."
mkdir -p "$(dirname "$TRANSCRIPT")"
CMDLINE="$CMDLINE pks_run=${TARGET} pks_auto=${TARGET} panic=1 systemd.mask=serial-getty@ttyS0.service"

TIMEOUT=(); command -v timeout >/dev/null 2>&1 && TIMEOUT=(timeout --kill-after=10s "${BATCH_TIMEOUT_SEC}s")

log_info "[exec/qemu] boot kernel=$KVAR mode=$MODE target=$TARGET -> $(basename "$TRANSCRIPT")"
# Headless capture: DO NOT use -nographic here. -nographic is built for an
# interactive tty and does not reliably deliver serial output when stdout is a
# plain file (it boots, but the transcript stays empty). The portable headless
# pattern is -display none + an explicit serial on stdio + no monitor, with
# stdin from /dev/null so the stdio chardev never blocks on a tty.
QEMU_ARGV=("$QEMU_BIN" "${COMMON_ARGS[@]}" -display none -serial stdio -monitor none -no-reboot -append "$CMDLINE")
# Record the exact command so a silent run can be reproduced by hand.
{ printf '### exec/qemu argv:\n'; printf '%q ' "${QEMU_ARGV[@]}"; printf '\n\n'; } > "$TRANSCRIPT"
start=$(date +%s)
# NB: never let a nonzero QEMU exit trip `set -e` before we log it.
if "${TIMEOUT[@]}" "${QEMU_ARGV[@]}" </dev/null >> "$TRANSCRIPT" 2>&1; then rc=0; else rc=$?; fi
elapsed=$(( $(date +%s) - start ))
echo "### exec/qemu exit=$rc elapsed=${elapsed}s" >> "$TRANSCRIPT"

if ! grep -q '^STATUS ' "$TRANSCRIPT" 2>/dev/null; then
    guest_bytes=$(grep -vE '^### ' "$TRANSCRIPT" | wc -c | tr -d ' ')
    log_warn "[exec/qemu] no STATUS (exit=$rc elapsed=${elapsed}s, ${guest_bytes} bytes of guest output)."
    case "$rc" in
        124|137) log_warn "[exec/qemu] QEMU hit the ${BATCH_TIMEOUT_SEC}s timeout -> it ran but produced no serial output (console not wired to stdio, or guest hung).";;
        0)       [ "$guest_bytes" -eq 0 ] && log_warn "[exec/qemu] QEMU exited 0 with no output -> likely never launched the guest.";;
        *)       log_warn "[exec/qemu] QEMU exited $rc before/at startup -> flag or environment rejection.";;
    esac
    log_warn "[exec/qemu] full transcript ($(basename "$TRANSCRIPT")):"
    sed 's/^/    | /' "$TRANSCRIPT" >&2
fi
