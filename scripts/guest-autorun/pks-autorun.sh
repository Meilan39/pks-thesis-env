#!/usr/bin/env bash
# scripts/guest-autorun/pks-autorun.sh - Headless automated test runner for QEMU guest
set -u

CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"
PKS_RUN=$(echo "$CMDLINE" | tr ' ' '\n' | grep -E '^pks_(run|auto)=' | cut -d= -f2 | tail -n1)
[ -z "$PKS_RUN" ] || [ "$PKS_RUN" = "shell" ] && exit 0

# 1. Mount 9p shared host workspace at /pks-thesis-env
if ! mountpoint -q /pks-thesis-env 2>/dev/null; then
    mkdir -p /pks-thesis-env
    mount -t 9p -o trans=virtio,version=9p2000.L,nofail pks_env /pks-thesis-env 2>/dev/null || true
fi
WORKSPACE="/pks-thesis-env"
[ -d "$WORKSPACE/tests" ] || WORKSPACE="/"

# 2. Determine mitigation mode and variant
PKS_MODE="off"
echo "$CMDLINE" | grep -q "pcache_pks=on" && PKS_MODE="on"
VARIANT="$PKS_MODE"
echo "$CMDLINE" | grep -q "pcache_control=1" && VARIANT="control"

# 3. Mount /mnt/protected on /dev/vda2 with pks_pagecache when enabled
if [ -b /dev/vda2 ]; then
    mkdir -p /mnt/protected
    mountpoint -q /mnt/protected && umount /mnt/protected 2>/dev/null || true
    MNT_OPT=$([ "$PKS_MODE" = "on" ] && echo "-o pks_pagecache" || echo "")
    mount $MNT_OPT /dev/vda2 /mnt/protected 2>/dev/null || true
fi

# 4. Dispatch target suite or individual script
run_suite() {
    local dir="$1" suite="$2"
    echo "[$suite] Executing suite ($PKS_RUN)..."
    for s in "$WORKSPACE/$dir"/*/run.sh; do
        [ -x "$s" ] && "$s" "$VARIANT"
    done
    echo "[$suite] Completed. [DONE]"
}

if [ -x "$PKS_RUN" ]; then
    "$PKS_RUN" "$VARIANT"
elif [ -x "$WORKSPACE/$PKS_RUN" ]; then
    "$WORKSPACE/$PKS_RUN" "$VARIANT"
elif [ -x "$WORKSPACE/perf/run.sh" ] && [[ "$PKS_RUN" =~ ^(perf|all_perf) ]]; then
    "$WORKSPACE/perf/run.sh" "$VARIANT"
else
    case "$PKS_RUN" in
        test|all_test|test-*) run_suite "tests" "test-${PKS_MODE}" ;;
        sec|all_sec|sec-*)   run_suite "sec" "sec-${PKS_MODE}" ;;
        perf|all_perf|perf-*) run_suite "perf" "perf-${VARIANT}" ;;
        *)
            for c in "$WORKSPACE/tests/$PKS_RUN/run.sh" "$WORKSPACE/sec/$PKS_RUN/run.sh" "$WORKSPACE/perf/$PKS_RUN/run.sh"; do
                [ -x "$c" ] && { "$c" "$VARIANT"; break; }
            done
            ;;
    esac
fi

sync && sleep 0.5 && poweroff -f
