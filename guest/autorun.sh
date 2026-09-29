#!/usr/bin/env bash
# guest/autorun.sh - In-guest dispatcher. Runs once at boot (via autorun.service),
# figures out what to run and in which mode, executes the workload leaves, and
# powers off. Leaves emit STATUS lines to stdout -> serial; the host harvests
# them from the transcript. This script writes NO canonical result files (a
# security panic would destroy them) - the serial stream is the transport.
#
# It also prints greppable "HB autorun:" breadcrumbs so a transcript that ends
# without STATUS still shows exactly how far boot/dispatch got.
set -u

hb() { echo "HB autorun: $*"; }

CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"
cmd_val() { printf '%s\n' "$CMDLINE" | tr ' ' '\n' | sed -n "s/^$1=//p" | tail -n1; }

hb "reached (cmdline: $CMDLINE)"

# Target: kernel cmdline (QEMU), overridden by /mnt/protected/.pks-run (bare-metal).
TARGET="$(cmd_val pks_run)"; [ -n "$TARGET" ] || TARGET="$(cmd_val pks_auto)"
[ -f /mnt/protected/.pks-run ] && TARGET="$(cat /mnt/protected/.pks-run 2>/dev/null || true)"
if [ -z "$TARGET" ] || [ "$TARGET" = shell ]; then hb "no run target; exiting"; exit 0; fi
hb "target=$TARGET"

# Mount the 9p host workspace.
if ! mountpoint -q /pks-thesis-env 2>/dev/null; then
    mkdir -p /pks-thesis-env
    mount -t 9p -o trans=virtio,version=9p2000.L,nofail pks_env /pks-thesis-env 2>/dev/null || true
fi
WS=/pks-thesis-env; [ -d "$WS/test" ] || WS=/
hb "9p_mounted=$(mountpoint -q /pks-thesis-env && echo yes || echo no) ws=$WS common.sh=$([ -f "$WS/common.sh" ] && echo yes || echo no)"

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
hb "protected_mounted=$(mountpoint -q /mnt/protected && echo yes || echo no) mode=$MODE label=$LABEL"

# Ensure debugfs is available for the diagnostic (sec) kernel.
mountpoint -q /sys/kernel/debug 2>/dev/null || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true

run_axis() {
    local s found=0
    for s in "$WS/$1"/*/run.sh; do [ -x "$s" ] && { found=1; "$s" "$LABEL"; }; done
    [ "$found" = 1 ] || hb "no executable run.sh under $WS/$1"
}

hb "dispatch target=$TARGET"
case "$TARGET" in
    test|sec|perf)  run_axis "$TARGET" ;;
    */*)            if [ -x "$WS/$TARGET/run.sh" ]; then "$WS/$TARGET/run.sh" "$LABEL"; else hb "missing $WS/$TARGET/run.sh"; fi ;;
    *)              for a in test sec perf; do
                        [ -x "$WS/$a/$TARGET/run.sh" ] && { "$WS/$a/$TARGET/run.sh" "$LABEL"; break; }
                    done ;;
esac

hb "done; powering off"
sync; sleep 0.5; poweroff -f
