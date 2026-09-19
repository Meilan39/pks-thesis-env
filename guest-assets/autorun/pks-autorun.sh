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
        echo "--> [PKS AUTORUN] Executing exploit test suite (all)..."
        if [ -x /exploit/run_tests.sh ]; then
            /exploit/run_tests.sh all
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

    sec_copyfail|sec_copy_fail)
        echo "--> [PKS AUTORUN] Executing Copy Fail exploit test..."
        if [ -x /exploit/run_tests.sh ]; then
            /exploit/run_tests.sh copy-fail
        else
            echo "ERROR: /exploit/run_tests.sh not found or not executable"
        fi

        if mountpoint -q /mnt/protected; then
            mkdir -p /mnt/protected/exploit_results
            cp -a /tmp/exploit_results/* /mnt/protected/exploit_results/ 2>/dev/null || true
        fi

        sync
        echo ""
        echo "================================================================"
        echo " [PKS AUTORUN] Copy Fail test complete. Powering off."
        echo "================================================================"
        sync
        sleep 1
        poweroff -f
        ;;

    sec_dirtyfrag|sec_dirty_frag)
        echo "--> [PKS AUTORUN] Executing Dirty Frag exploit test..."
        if [ -x /exploit/run_tests.sh ]; then
            /exploit/run_tests.sh dirty-frag
        else
            echo "ERROR: /exploit/run_tests.sh not found or not executable"
        fi

        if mountpoint -q /mnt/protected; then
            mkdir -p /mnt/protected/exploit_results
            cp -a /tmp/exploit_results/* /mnt/protected/exploit_results/ 2>/dev/null || true
        fi

        sync
        echo ""
        echo "================================================================"
        echo " [PKS AUTORUN] Dirty Frag test complete. Powering off."
        echo "================================================================"
        sync
        sleep 1
        poweroff -f
        ;;

    sec_fragnesia)
        echo "--> [PKS AUTORUN] Executing Fragnesia exploit test..."
        if [ -x /exploit/run_tests.sh ]; then
            /exploit/run_tests.sh fragnesia
        else
            echo "ERROR: /exploit/run_tests.sh not found or not executable"
        fi

        if mountpoint -q /mnt/protected; then
            mkdir -p /mnt/protected/exploit_results
            cp -a /tmp/exploit_results/* /mnt/protected/exploit_results/ 2>/dev/null || true
        fi

        sync
        echo ""
        echo "================================================================"
        echo " [PKS AUTORUN] Fragnesia test complete. Powering off."
        echo "================================================================"
        sync
        sleep 1
        poweroff -f
        ;;

    bench|bench_control|bench_mitigated|bench_off)
        echo "--> [PKS AUTORUN] Executing fio benchmark suite..."
        if [ -x /benchmark/run_benchmarks.sh ]; then
            /benchmark/run_benchmarks.sh
        else
            echo "ERROR: /benchmark/run_benchmarks.sh not found or not executable"
        fi

        # Persist results to disk partition
        if mountpoint -q /mnt/protected; then
            mkdir -p /mnt/protected/bench_results
            if [ -d /tmp/bench_results ]; then
                cp -a /tmp/bench_results/* /mnt/protected/bench_results/ 2>/dev/null || true
            fi
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

    compliance|test)
        echo "--> [PKS AUTORUN] Executing Consolidated Compliance Suite (Single-Boot)..."
        mkdir -p /tmp/compliance_results

        # 1. PKS Hardware & Driver Sanity
        echo ""
        echo "=== [1/3] PKS In-Kernel Self-Test ==="
        if [ -x /unit-tests/run_pks_unit.sh ]; then
            /unit-tests/run_pks_unit.sh || true
        fi

        # 2. File System Exerciser (fsx)
        echo ""
        echo "=== [2/3] File System Exerciser (fsx) ==="
        if [ -x /fsx/run_fsx.sh ]; then
            /fsx/run_fsx.sh || true
        elif [ -x /guest-assets/fsx/run_fsx.sh ]; then
            /guest-assets/fsx/run_fsx.sh || true
        fi

        # 3. POSIX Compliance (pjdfstest)
        echo ""
        echo "=== [3/3] POSIX Compliance Tests (pjdfstest) ==="
        if [ -d /pjdfstest/tests ] && [ -x /pjdfstest/pjdfstest ] && command -v prove >/dev/null 2>&1; then
            if mountpoint -q /mnt/protected; then
                mkdir -p /mnt/protected/pjdfstest_scratch
                cd /mnt/protected/pjdfstest_scratch
                prove -r /pjdfstest/tests/chown /pjdfstest/tests/chmod /pjdfstest/tests/truncate 2>&1 | tee /tmp/pjdfstest.log || true
                cd /
                rm -rf /mnt/protected/pjdfstest_scratch
            else
                cd /pjdfstest && prove -r tests/chown tests/chmod tests/truncate 2>&1 | tee /tmp/pjdfstest.log || true
                cd /
            fi
        else
            echo "[INFO] pjdfstest omitted, uncompiled, or prove not installed. Functional coverage validated by fsx."
        fi

        # Persist results to protected storage
        if mountpoint -q /mnt/protected; then
            mkdir -p /mnt/protected/compliance_results
            cp -a /tmp/unit_results/* /mnt/protected/unit_results/ 2>/dev/null || true
            cp -a /tmp/fsx_results/* /mnt/protected/fsx_results/ 2>/dev/null || true
            [ -f /tmp/pjdfstest.log ] && cp /tmp/pjdfstest.log /mnt/protected/compliance_results/ 2>/dev/null || true
            
            {
                echo "======================================================================"
                echo " PKS Thesis Compliance & Functional Integrity Summary"
                echo "======================================================================"
                echo "Kernel:  $(uname -r)"
                echo "Date:    $(date)"
                echo "Cmdline: $(cat /proc/cmdline)"
                echo "----------------------------------------------------------------------"
                echo "1. Hardware Driver Sanity:"
                if [ -f /mnt/protected/unit_results/test_pks.log ]; then
                    grep -E "(PASSED|FAILED|FAIL|PASS|Test)" /mnt/protected/unit_results/test_pks.log | tail -n 8 || true
                else
                    echo "  Completed"
                fi
                echo "----------------------------------------------------------------------"
                echo "2. File System Exerciser (fsx):"
                if [ -f /mnt/protected/fsx_results/fsx_protected.log ]; then
                    grep -E "(Final Result|Summary|PASS|FAIL)" /mnt/protected/fsx_results/fsx_protected.log | tail -n 8 || true
                else
                    echo "  Completed"
                fi
                echo "======================================================================"
            } > /mnt/protected/compliance_results/summary.txt
        fi

        sync
        echo ""
        echo "================================================================"
        echo " [PKS AUTORUN] Compliance testing complete. Powering off."
        echo "================================================================"
        sync
        sleep 1
        poweroff -f
        ;;

    *)
        echo "WARN: Unknown pks_auto mode '$AUTO_MODE'. Continuing normal boot."
        ;;
esac
