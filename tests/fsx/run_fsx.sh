#!/usr/bin/env bash
# ==============================================================================
# guest-assets/fsx/run_fsx.sh - Automated fsx validation harness
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FSX_BIN="$SCRIPT_DIR/fsx"
RESULTS_DIR="${RESULTS_DIR:-/tmp/fsx_results}"
PROTECTED_MOUNT="/mnt/protected"

mkdir -p "$RESULTS_DIR"

echo "================================================================"
echo " File System Exerciser (fsx) - Automated PKS Test Suite"
echo "================================================================"

# Compile fsx if binary is missing
if [ ! -x "$FSX_BIN" ]; then
    echo "[INFO] Compiling fsx binary..."
    make -C "$SCRIPT_DIR" >/dev/null 2>&1 || gcc -O2 -Wall -o "$FSX_BIN" "$SCRIPT_DIR/fsx.c"
fi

if [ ! -x "$FSX_BIN" ]; then
    echo "[ERR]  Failed to compile or find fsx binary at $FSX_BIN"
    exit 1
fi

# Ensure /mnt/protected is mounted with proper options
CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"
mkdir -p "$PROTECTED_MOUNT"

if echo "$CMDLINE" | grep -q "pcache_pks=on"; then
    if mountpoint -q "$PROTECTED_MOUNT"; then
        if ! grep "$PROTECTED_MOUNT" /proc/mounts | grep -q "pks_pagecache"; then
            echo "[INFO] Re-mounting $PROTECTED_MOUNT with 'pks_pagecache'..."
            umount "$PROTECTED_MOUNT" 2>/dev/null || true
            mount -o pks_pagecache /dev/vda2 "$PROTECTED_MOUNT" 2>/dev/null || true
        fi
    else
        echo "[INFO] Mounting $PROTECTED_MOUNT with 'pks_pagecache'..."
        mount -o pks_pagecache /dev/vda2 "$PROTECTED_MOUNT" 2>/dev/null || true
    fi

    if grep "$PROTECTED_MOUNT" /proc/mounts | grep -q "pks_pagecache"; then
        echo "[OK]   Protected mount active: $PROTECTED_MOUNT with 'pks_pagecache'"
    else
        echo "[ERR]  Failed to mount $PROTECTED_MOUNT with 'pks_pagecache'!"
    fi
else
    if ! mountpoint -q "$PROTECTED_MOUNT"; then
        echo "[INFO] Mounting $PROTECTED_MOUNT (standard ext4)..."
        mount /dev/vda2 "$PROTECTED_MOUNT" 2>/dev/null || true
    fi
    echo "[INFO] Mount active: $PROTECTED_MOUNT (standard ext4, pcache_pks=off)"
fi

TOTAL_PASS=0
TOTAL_TESTS=3

printf "\n %-4s | %-42s | %-8s\n" "Test" "Description" "Result"
printf "%s\n" "------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# Test 1: Standard Rootfs Exerciser (All Ops, including MAPWRITE)
# ------------------------------------------------------------------------------
TEST1_LOG="$RESULTS_DIR/fsx_rootfs.log"
"$FSX_BIN" -N 5000 -l 16777216 /tmp/fsx_rootfs.bin >"$TEST1_LOG" 2>&1
rc=$?
if [ $rc -eq 0 ] && grep -q "SUCCESS" "$TEST1_LOG"; then
    res1="[PASS]"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    res1="[FAIL]"
fi
printf " 1    | Rootfs vanilla ext4 (5K ops, all features) | %-8s\n" "$res1"

# ------------------------------------------------------------------------------
# Test 2: Protected Mount In-Scope Exerciser (Read, Write, Truncate, MapRead)
# ------------------------------------------------------------------------------
TEST2_LOG="$RESULTS_DIR/fsx_protected.log"
if mountpoint -q "$PROTECTED_MOUNT"; then
    # -W disables MAPWRITE (Commit 06 scope exclusion)
    "$FSX_BIN" -N 10000 -l 67108864 -W "$PROTECTED_MOUNT/fsx_prot.bin" >"$TEST2_LOG" 2>&1
    rc=$?
    if [ $rc -eq 0 ] && grep -q "SUCCESS" "$TEST2_LOG"; then
        res2="[PASS]"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        res2="[FAIL]"
    fi
else
    res2="[SKIP]"
    echo "[WARN] $PROTECTED_MOUNT not mounted, skipping Test 2" >"$TEST2_LOG"
fi
printf " 2    | Protected mount in-scope (10K ops, 64MB)   | %-8s\n" "$res2"

# ------------------------------------------------------------------------------
# Test 3: Negative Test: Confirm Commit 06 MAP_SHARED writable mmap rejection
# ------------------------------------------------------------------------------
TEST3_LOG="$RESULTS_DIR/fsx_mapwrite_reject.log"
if mountpoint -q "$PROTECTED_MOUNT"; then
    if grep "$PROTECTED_MOUNT" /proc/mounts | grep -q "pks_pagecache"; then
        # On protected mount: verify MAP_SHARED writable mmap fails with -EOPNOTSUPP
        "$FSX_BIN" -b "$PROTECTED_MOUNT/fsx_reject.bin" >"$TEST3_LOG" 2>&1
        rc=$?
        if [ $rc -eq 0 ]; then
            res3="[PASS]"
            TOTAL_PASS=$((TOTAL_PASS + 1))
        else
            res3="[FAIL]"
        fi
    else
        # On unprotected mount (pcache_pks=off): verify MAP_SHARED writable mmap is permitted (rc=3)
        "$FSX_BIN" -b "$PROTECTED_MOUNT/fsx_reject.bin" >"$TEST3_LOG" 2>&1
        rc=$?
        if [ $rc -eq 3 ]; then
            res3="[PASS]"
            TOTAL_PASS=$((TOTAL_PASS + 1))
        else
            res3="[FAIL]"
        fi
    fi
else
    res3="[SKIP]"
    echo "[WARN] $PROTECTED_MOUNT not mounted, skipping Test 3" >"$TEST3_LOG"
fi
printf " 3    | Commit 06 policy (verify -EOPNOTSUPP mmap) | %-8s\n" "$res3"

printf "%s\n" "------------------------------------------------------------------"
echo " Summary: $TOTAL_PASS / $TOTAL_TESTS test phases passed"
echo ""

# Persist output to protected partition
if mountpoint -q "$PROTECTED_MOUNT"; then
    mkdir -p "$PROTECTED_MOUNT/fsx_results"
    cp -a "$RESULTS_DIR"/* "$PROTECTED_MOUNT/fsx_results/" 2>/dev/null || true
fi

if [ "$TOTAL_PASS" -eq "$TOTAL_TESTS" ]; then
    echo "[OK]   All fsx filesystem exerciser tests passed without data corruption."
    exit 0
else
    echo "[ERR]  One or more fsx filesystem tests failed. Inspect logs in $RESULTS_DIR"
    exit 1
fi
