#!/usr/bin/env bash
# guest/autorun.sh - In-guest dispatcher. Runs once at boot (via autorun.service),
# figures out what to run and in which mode, executes the workload leaves, and
# powers off. Leaves emit STATUS lines to stdout -> serial; the host harvests
# them from the transcript. This script writes NO canonical result files (a
# security panic would destroy them) - the serial stream is the transport.
set -u

CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"
cmd_val() { printf '%s\n' "$CMDLINE" | tr ' ' '\n' | sed -n "s/^$1=//p" | tail -n1; }

# Target: kernel cmdline (QEMU), overridden by /mnt/protected/.pks-run (bare-metal).
TARGET="$(cmd_val pks_run)"; [ -n "$TARGET" ] || TARGET="$(cmd_val pks_auto)"
[ -f /mnt/protected/.pks-run ] && TARGET="$(cat /mnt/protected/.pks-run 2>/dev/null || true)"
{ [ -z "$TARGET" ] || [ "$TARGET" = shell ]; } && exit 0

# Mount the 9p host workspace.
if ! mountpoint -q /pks-thesis-env 2>/dev/null; then
    mkdir -p /pks-thesis-env
    mount -t 9p -o trans=virtio,version=9p2000.L,nofail pks_env /pks-thesis-env 2>/dev/null || true
fi
WS=/pks-thesis-env; [ -d "$WS/test" ] || WS=/

# Determine mode + experimental-condition label.
MODE=off; printf '%s' "$CMDLINE" | grep -q pcache_pks=on && MODE=on
LABEL=$MODE; printf '%s' "$CMDLINE" | grep -q pcache_control=1 && LABEL=control

# Mount the protected evaluation volume (with the PKS option when enabled).
if [ -b /dev/vda2 ]; then
    mkdir -p /mnt/protected
    mountpoint -q /mnt/protected && umount /mnt/protected 2>/dev/null || true
    OPT=""; [ "$MODE" = on ] && OPT="-o pks_pagecache"
    mount $OPT /dev/vda2 /mnt/protected 2>/dev/null || true
fi

# Ensure debugfs is available for the diagnostic (sec) kernel.
mountpoint -q /sys/kernel/debug 2>/dev/null || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true

run_axis() { local s; for s in "$WS/$1"/*/run.sh; do [ -x "$s" ] && "$s" "$LABEL"; done; }

case "$TARGET" in
    test|sec|perf)  run_axis "$TARGET" ;;
    */*)            [ -x "$WS/$TARGET/run.sh" ] && "$WS/$TARGET/run.sh" "$LABEL" ;;   # e.g. sec/copy-fail
    *)              for a in test sec perf; do
                        [ -x "$WS/$a/$TARGET/run.sh" ] && { "$WS/$a/$TARGET/run.sh" "$LABEL"; break; }
                    done ;;
esac

sync; sleep 0.5; poweroff -f
