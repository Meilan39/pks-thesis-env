#!/usr/bin/env bash
# ==============================================================================
# exec/baremetal.sh - Bare-metal substrate adapter (executor contract)
# ==============================================================================
#     exec/baremetal.sh <kernel_variant> <pks_mode> <target> [transcript_out]
#
#   kernel_variant : control | sec | perf  (which kernel must be booted)
#   pks_mode       : on | off               (pcache_pks=; ignored for control)
#   target         : shell             -> interactive login shell, OR
#                    test | sec | perf -> run all leaves of an axis, OR
#                    <axis>/<leaf>     -> run one leaf (e.g. sec/copy-fail)
#   transcript_out : host path for the captured transcript (headless only)
#
# Unlike the QEMU adapter, this does NOT boot anything: a physical boot serves
# exactly one (kernel_variant, pks_mode), so the adapter verifies that the
# RUNNING kernel matches the request, then runs the leaves natively and captures
# both their stdout and the live kernel log (/dev/kmsg via dmesg) into the
# transcript -- the same grep contract the QEMU serial transcript provides.
#
# This yields zero-virtualization-overhead performance numbers. Drive the full
# off/on/control matrix by rebooting into each config (grub-reboot one-shot) and
# invoking the matching axis under EXECUTOR=baremetal; see context/benchmark-plan-6.md.
#
# Prerequisites on the test host:
#   * booted into the matching patched kernel + cmdline (pcache_pks=on|off or
#     pcache_control=1), with real-hardware drivers (configs/baremetal.config);
#   * a dedicated evaluation partition PROTECTED_DEV (never the rootfs);
#   * run as root; repo checked out locally at REPO_ROOT.
#   * perf boots additionally carry isolation/tuning cmdline (isolcpus=,
#     nohz_full=, intel_idle.max_cstate=1) -- see the perf grub entry.
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

PROTECTED_DEV="${PROTECTED_DEV:-/dev/sdb1}"
PROTECTED_MNT="${PROTECTED_MNT:-/mnt/protected}"
BATCH_TIMEOUT_SEC="${BATCH_TIMEOUT_SEC:-0}"

[ "$(id -u)" -eq 0 ] || die "exec/baremetal.sh must run as root (mount, drop_caches)."

# ------------------------------------------------------------------------------
# Verify the running kernel matches the requested (variant, mode)
# ------------------------------------------------------------------------------
# A boot cannot change variant or mode; those are fixed at boot. Confirm the
# live kernel is the one asked for and refuse (rather than silently mismeasure)
# otherwise. PKS_KEXEC is reserved for a future auto-kexec driver.
CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"
running_mode="off"
printf '%s' "$CMDLINE" | grep -q 'pcache_pks=on' && running_mode="on"
running_label="$running_mode"
printf '%s' "$CMDLINE" | grep -q 'pcache_control=1' && running_label="control"

want_label="$PKS_MODE"
[ "$KERNEL_VARIANT" = "control" ] && want_label="control"

if [ "$running_label" != "$want_label" ]; then
    die "host is booted as '$running_label' but '$want_label' was requested; reboot into the matching kernel/mode (grub-reboot) first."
fi

# ------------------------------------------------------------------------------
# Interactive shell
# ------------------------------------------------------------------------------
if [ "$TARGET" = "shell" ]; then
    log_info "Native shell (kernel=$KERNEL_VARIANT mode=$running_label). Leaves run on real silicon."
    exec "${SHELL:-/bin/bash}"
fi

# ------------------------------------------------------------------------------
# Headless capture setup
# ------------------------------------------------------------------------------
[ -n "$TRANSCRIPT_PATH" ] || die "Headless run requires a transcript path (argument 4)."
mkdir -p "$(dirname "$TRANSCRIPT_PATH")"

{
    printf '### exec/baremetal host=%s kernel=%s mode=%s target=%s\n' \
        "$(uname -nr)" "$KERNEL_VARIANT" "$running_label" "$TARGET"
    printf '### cmdline: %s\n\n' "$CMDLINE"
} > "$TRANSCRIPT_PATH"

# Follow the kernel log so neutralization ("suppressed stray store", "unauthorized
# write") and any panic/oops land in the transcript exactly as they would on the
# QEMU serial line. Prefer --follow-new (only new lines); else dump+follow.
if dmesg --help 2>&1 | grep -q -- '--follow-new'; then
    dmesg --follow-new >> "$TRANSCRIPT_PATH" 2>/dev/null &
else
    dmesg --follow     >> "$TRANSCRIPT_PATH" 2>/dev/null &
fi
KLOG_PID=$!
cleanup() { [ -n "${KLOG_PID:-}" ] && kill "$KLOG_PID" 2>/dev/null || true; }
trap cleanup EXIT

log_info "[exec/baremetal] native run kernel=$KERNEL_VARIANT mode=$running_label target=$TARGET -> $(basename "$TRANSCRIPT_PATH")"

# ------------------------------------------------------------------------------
# Mount the dedicated evaluation partition per mode (mirror guest/autorun.sh)
# ------------------------------------------------------------------------------
if [ -b "$PROTECTED_DEV" ]; then
    mkdir -p "$PROTECTED_MNT"
    if [ "$running_mode" = "on" ]; then
        if ! grep -q "${PROTECTED_MNT}.*pks_pagecache" /proc/mounts 2>/dev/null; then
            umount -l "$PROTECTED_MNT" 2>/dev/null || true
            mount -o pks_pagecache "$PROTECTED_DEV" "$PROTECTED_MNT" 2>/dev/null \
                || die "mount -o pks_pagecache $PROTECTED_DEV failed (kernel PKS pool inactive?)."
        fi
    else
        if grep -q "${PROTECTED_MNT}.*pks_pagecache" /proc/mounts 2>/dev/null; then
            umount -l "$PROTECTED_MNT" 2>/dev/null || true
            mount "$PROTECTED_DEV" "$PROTECTED_MNT" 2>/dev/null || true
        elif ! mountpoint -q "$PROTECTED_MNT" 2>/dev/null; then
            mount "$PROTECTED_DEV" "$PROTECTED_MNT" 2>/dev/null || true
        fi
    fi
else
    log_warn "[exec/baremetal] PROTECTED_DEV=$PROTECTED_DEV not found; leaves will fall back to /tmp."
fi

mountpoint -q /sys/kernel/debug 2>/dev/null || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true

# ------------------------------------------------------------------------------
# Performance hygiene (best-effort) for no-overhead perf numbers
# ------------------------------------------------------------------------------
# Boot-time isolation (isolcpus=, nohz_full=, intel_idle.max_cstate=1) must come
# from the perf grub entry; here we pin frequency/turbo at runtime.
perf_tune() {
    command -v cpupower >/dev/null 2>&1 && cpupower frequency-set -g performance >/dev/null 2>&1 || true
    local g
    for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance > "$g" 2>/dev/null || true
    done
    echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true
    log_info "[exec/baremetal] perf hygiene applied (governor=performance, turbo off)."
}

# ------------------------------------------------------------------------------
# Dispatch (mirror guest/autorun.sh: LABEL as $1, per-leaf delimiter)
# ------------------------------------------------------------------------------
TIMEOUT=()
if [ "$BATCH_TIMEOUT_SEC" -gt 0 ] 2>/dev/null && command -v timeout >/dev/null 2>&1; then
    TIMEOUT=(timeout --kill-after=10s "${BATCH_TIMEOUT_SEC}s")
fi

run_leaf() {
    local script="$1"
    local leaf
    leaf="$(basename "$(dirname "$script")")"
    {
        echo "### PKS-LEAF $leaf"
        "${TIMEOUT[@]}" "$script" "$running_label" || true
    } 2>&1 | tee -a "$TRANSCRIPT_PATH"
}

case "$TARGET" in
    perf|perf/*) perf_tune ;;
esac

case "$TARGET" in
    test|sec|perf)
        found=0
        for script in "$REPO_ROOT/$TARGET"/*/run.sh; do
            [ -x "$script" ] && { found=1; run_leaf "$script"; }
        done
        [ "$found" -eq 1 ] || log_warn "[exec/baremetal] no executable run.sh under $REPO_ROOT/$TARGET"
        ;;
    */*)
        if [ -x "$REPO_ROOT/$TARGET/run.sh" ]; then
            run_leaf "$REPO_ROOT/$TARGET/run.sh"
        else
            die "missing $REPO_ROOT/$TARGET/run.sh"
        fi
        ;;
    *)
        matched=0
        for axis in test sec perf; do
            if [ -x "$REPO_ROOT/$axis/$TARGET/run.sh" ]; then
                run_leaf "$REPO_ROOT/$axis/$TARGET/run.sh"
                matched=1
                break
            fi
        done
        [ "$matched" -eq 1 ] || die "no leaf matches target '$TARGET'"
        ;;
esac

sync
# Give the backgrounded dmesg follower a beat to flush trailing lines.
sleep 1
echo "### exec/baremetal done" >> "$TRANSCRIPT_PATH"
