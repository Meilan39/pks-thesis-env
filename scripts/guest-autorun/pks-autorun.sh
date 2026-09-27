#!/usr/bin/env bash
# scripts/guest-autorun/pks-autorun.sh - Headless automated test runner for QEMU guest
set -u

CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"

PKS_RUN=""
for param in $CMDLINE; do
    case "$param" in
        pks_run=*)
            PKS_RUN="${param#pks_run=}"
            ;;
        pks_auto=*)
            PKS_RUN="${param#pks_auto=}"
            ;;
    esac
done

if [ -z "$PKS_RUN" ] || [ "$PKS_RUN" = "shell" ]; then
    exit 0
fi

# 1. Mount 9p shared host workspace at /pks-thesis-env if available
if ! mountpoint -q /pks-thesis-env 2>/dev/null; then
    mkdir -p /pks-thesis-env
    mount -t 9p -o trans=virtio,version=9p2000.L,nofail pks_env /pks-thesis-env 2>/dev/null || true
fi

WORKSPACE="/pks-thesis-env"
[ -d "$WORKSPACE/tests" ] || WORKSPACE="/"

# 2. Determine mitigation mode and variant from cmdline
PKS_MODE="off"
echo "$CMDLINE" | grep -q "pcache_pks=on" && PKS_MODE="on"

VARIANT="on"
if echo "$CMDLINE" | grep -q "pcache_control=1"; then
    VARIANT="control"
elif [ "$PKS_MODE" = "off" ]; then
    VARIANT="off"
fi

# 3. Mount /mnt/protected on /dev/vda2 with pks_pagecache when enabled
if [ -b /dev/vda2 ]; then
    mkdir -p /mnt/protected
    if [ "$PKS_MODE" = "on" ]; then
        if mountpoint -q /mnt/protected; then
            if ! grep "/mnt/protected" /proc/mounts | grep -q "pks_pagecache"; then
                umount /mnt/protected 2>/dev/null || true
                mount -o pks_pagecache /dev/vda2 /mnt/protected 2>/dev/null || true
            fi
        else
            mount -o pks_pagecache /dev/vda2 /mnt/protected 2>/dev/null || true
        fi
    else
        if ! mountpoint -q /mnt/protected; then
            mount /dev/vda2 /mnt/protected 2>/dev/null || true
        fi
    fi
fi

# 4. Dispatch target script directly or execute consolidated suites
if [ -x "$PKS_RUN" ]; then
    "$PKS_RUN" "$VARIANT"
elif [ -x "$WORKSPACE/$PKS_RUN" ]; then
    "$WORKSPACE/$PKS_RUN" "$VARIANT"
else
    case "$PKS_RUN" in
        test|all_test|test-on|test-off)
            echo "[test-${PKS_MODE}] Starting consolidated compliance run (pcache_pks=${PKS_MODE})..."
            echo ""
            [ -x "$WORKSPACE/tests/pks-unit/run.sh" ] && "$WORKSPACE/tests/pks-unit/run.sh"
            [ -x "$WORKSPACE/tests/sanity/run.sh" ] && "$WORKSPACE/tests/sanity/run.sh"
            [ -x "$WORKSPACE/tests/fsx/run.sh" ] && "$WORKSPACE/tests/fsx/run.sh"
            [ -x "$WORKSPACE/tests/pjd/run.sh" ] && "$WORKSPACE/tests/pjd/run.sh"
            echo "[test-${PKS_MODE}] Consolidated compliance run completed. [DONE]"
            echo ""
            ;;
        sec|all_sec|sec-on|sec-off)
            echo "[sec-${PKS_MODE}] Starting exploit suite under active mitigation (pcache_pks=${PKS_MODE})..."
            echo ""
            [ -x "$WORKSPACE/sec/copy-fail/run.sh" ] && "$WORKSPACE/sec/copy-fail/run.sh"
            [ -x "$WORKSPACE/sec/dirty-frag/run.sh" ] && "$WORKSPACE/sec/dirty-frag/run.sh"
            [ -x "$WORKSPACE/sec/fragnesia/run.sh" ] && "$WORKSPACE/sec/fragnesia/run.sh"
            echo "[sec-${PKS_MODE}] Exploit suite execution completed. [DONE]"
            echo ""
            ;;
        perf|all_perf|perf-control|perf-off|perf-on)
            echo "[perf-${VARIANT}] Running benchmark VM for ${VARIANT}..."
            echo ""
            [ -x "$WORKSPACE/perf/fio/run_warm.sh" ] && "$WORKSPACE/perf/fio/run_warm.sh" "$VARIANT"
            [ -x "$WORKSPACE/perf/fio/run_cold.sh" ] && "$WORKSPACE/perf/fio/run_cold.sh" "$VARIANT"
            [ -x "$WORKSPACE/perf/concurrency/run.sh" ] && "$WORKSPACE/perf/concurrency/run.sh" "$VARIANT"
            [ -x "$WORKSPACE/perf/sqlite/run.sh" ] && "$WORKSPACE/perf/sqlite/run.sh" "$VARIANT"
            echo "[perf-${VARIANT}] Benchmark run completed. [DONE]"
            echo ""
            ;;
        *)
            # Fallback path discovery
            for candidate in "$WORKSPACE/tests/$PKS_RUN/run.sh" "$WORKSPACE/sec/$PKS_RUN/run.sh" "$WORKSPACE/perf/$PKS_RUN/run.sh"; do
                if [ -x "$candidate" ]; then
                    "$candidate" "$VARIANT"
                    break
                fi
            done
            ;;
    esac
fi

# 5. Flush filesystem state and clean poweroff
sync
sleep 0.5
poweroff -f
