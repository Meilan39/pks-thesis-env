#!/usr/bin/env bash
# ==============================================================================
# /usr/local/bin/pks-autorun.sh - Headless automated test runner for QEMU guest
# ==============================================================================
# Triggered at systemd multi-user.target when 'pks_auto=<target>' is in /proc/cmdline.
# ==============================================================================
set -u

CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"

# Extract pks_auto parameter
AUTO_MODE=""
for param in $CMDLINE; do
    case "$param" in
        pks_auto=*)
            AUTO_MODE="${param#pks_auto=}"
            ;;
    esac
done

if [ -z "$AUTO_MODE" ]; then
    exit 0
fi

echo ""
echo "================================================================"
echo " [PKS AUTORUN] Triggered with mode: $AUTO_MODE"
echo "================================================================"

# Ensure /mnt/protected is mounted with proper options if partition exists
if [ -b /dev/vda2 ]; then
    mkdir -p /mnt/protected
    if echo "$CMDLINE" | grep -q "pcache_pks=on"; then
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
            mount /dev/vda2 /mnt/protected 2>/dev/null || mount -t ext4 /dev/vda2 /mnt/protected 2>/dev/null || true
        fi
    fi
fi

case "$AUTO_MODE" in
    sec|sec_on|sec_off)
        echo "--> [PKS AUTORUN] Executing exploit test suite..."
        if [ -x /exploit/run_tests.sh ]; then
            /exploit/run_tests.sh
        else
            echo "ERROR: /exploit/run_tests.sh not found or not executable"
        fi

        # Persist results to disk partition
        if mountpoint -q /mnt/protected; then
            mkdir -p /mnt/protected/exploit_results
            cp -a /tmp/exploit_results/* /mnt/protected/exploit_results/ 2>/dev/null || true
        fi

        sync
        echo ""
        echo "================================================================"
        echo " [PKS AUTORUN] Security validation complete. Powering off."
        echo "================================================================"
        sync
        sleep 1
        poweroff -f
        ;;

    bench|bench_control|bench_mitigated)
        echo "--> [PKS AUTORUN] Executing fio benchmark suite..."
        if [ -x /benchmark/run_benchmarks.sh ]; then
            /benchmark/run_benchmarks.sh
        else
            echo "ERROR: /benchmark/run_benchmarks.sh not found or not executable"
        fi

        # Persist results to disk partition
        if mountpoint -q /mnt/protected; then
            mkdir -p /mnt/protected/bench_results
            cp -a /tmp/bench_results/* /mnt/protected/bench_results/ 2>/dev/null || true
        fi

        sync
        echo ""
        echo "================================================================"
        echo " [PKS AUTORUN] Benchmarking complete. Powering off."
        echo "================================================================"
        sync
        sleep 1
        poweroff -f
        ;;

    unit|pks_unit)
        echo "--> [PKS AUTORUN] Executing in-kernel PKS unit test suite..."
        if [ -x /unit-tests/run_pks_unit.sh ]; then
            /unit-tests/run_pks_unit.sh
        else
            echo "ERROR: /unit-tests/run_pks_unit.sh not found or not executable"
        fi

        # Persist results to disk partition
        if mountpoint -q /mnt/protected; then
            mkdir -p /mnt/protected/unit_results
            cp -a /tmp/unit_results/* /mnt/protected/unit_results/ 2>/dev/null || true
        fi

        sync
        echo ""
        echo "================================================================"
        echo " [PKS AUTORUN] PKS unit testing complete. Powering off."
        echo "================================================================"
        sync
        sleep 1
        poweroff -f
        ;;

    fsx|selftest|selftests)
        echo "--> [PKS AUTORUN] Executing fsx filesystem exerciser suite..."
        if [ -x /fsx/run_fsx.sh ]; then
            /fsx/run_fsx.sh
        elif [ -x /guest-assets/fsx/run_fsx.sh ]; then
            /guest-assets/fsx/run_fsx.sh
        else
            echo "ERROR: run_fsx.sh not found or not executable"
        fi

        # Persist results to disk partition
        if mountpoint -q /mnt/protected; then
            mkdir -p /mnt/protected/fsx_results
            cp -a /tmp/fsx_results/* /mnt/protected/fsx_results/ 2>/dev/null || true
        fi

        sync
        echo ""
        echo "================================================================"
        echo " [PKS AUTORUN] fsx filesystem exerciser complete. Powering off."
        echo "================================================================"
        sync
        sleep 1
        poweroff -f
        ;;

    *)
        echo "WARN: Unknown pks_auto mode '$AUTO_MODE'. Continuing normal boot."
        ;;
esac
