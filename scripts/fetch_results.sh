#!/usr/bin/env bash
# ==============================================================================
# scripts/fetch_results.sh - Extract benchmark & test artifacts from disk image
# ==============================================================================
# Usage: ./fetch_results.sh [destination_dir]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
DEST_DIR="${1:-${RESULTS_DIR:-$ENV_DIR/results}/extracted}"

[ -f "$DISK_IMG" ] || die "Disk image not found: $DISK_IMG"
require_cmds losetup mount umount sudo

log_header "Extracting Artifacts from Disk Image"
log_kv "Disk Image"  "$DISK_IMG"
log_kv "Destination" "$DEST_DIR"

log_step "Attaching disk image as loop device"
LOOP=$(sudo losetup --find --show --partscan "$DISK_IMG")
PROT_PART="${LOOP}p2"
ROOT_PART="${LOOP}p1"

MOUNT_POINT="$(mktemp -d)"

cleanup() {
    log_step "Detaching loop devices and mounts"
    sudo umount "$MOUNT_POINT" 2>/dev/null || true
    sudo losetup -d "$LOOP" 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$DEST_DIR/bench" "$DEST_DIR/exploit" "$DEST_DIR/unit" "$DEST_DIR/fsx"

# 1. Check protected partition (partition 2)
if [ -b "$PROT_PART" ]; then
    log_step "Inspecting protected storage partition ($PROT_PART)"
    if sudo mount -o ro "$PROT_PART" "$MOUNT_POINT" 2>/dev/null; then
        if [ -d "$MOUNT_POINT/bench_results" ]; then
            log_info "Harvesting benchmark data from protected partition..."
            sudo cp -a "$MOUNT_POINT/bench_results/." "$DEST_DIR/bench/" 2>/dev/null || true
        fi
        if [ -d "$MOUNT_POINT/exploit_results" ]; then
            log_info "Harvesting exploit logs from protected partition..."
            sudo cp -a "$MOUNT_POINT/exploit_results/." "$DEST_DIR/exploit/" 2>/dev/null || true
        fi
        if [ -d "$MOUNT_POINT/unit_results" ]; then
            log_info "Harvesting unit test logs from protected partition..."
            sudo cp -a "$MOUNT_POINT/unit_results/." "$DEST_DIR/unit/" 2>/dev/null || true
        fi
        if [ -d "$MOUNT_POINT/fsx_results" ]; then
            log_info "Harvesting fsx test logs from protected partition..."
            sudo cp -a "$MOUNT_POINT/fsx_results/." "$DEST_DIR/fsx/" 2>/dev/null || true
        fi
        sudo umount "$MOUNT_POINT"
    fi
fi

# 2. Check rootfs /tmp if files were left in root partition (without clobbering protected partition data)
if [ -b "$ROOT_PART" ]; then
    log_step "Inspecting rootfs partition ($ROOT_PART)"
    if sudo mount -o ro "$ROOT_PART" "$MOUNT_POINT" 2>/dev/null; then
        if [ -d "$MOUNT_POINT/tmp/bench_results" ]; then
            sudo cp -a -n "$MOUNT_POINT/tmp/bench_results/." "$DEST_DIR/bench/" 2>/dev/null || true
        fi
        if [ -d "$MOUNT_POINT/tmp/exploit_results" ]; then
            sudo cp -a -n "$MOUNT_POINT/tmp/exploit_results/." "$DEST_DIR/exploit/" 2>/dev/null || true
        fi
        if [ -d "$MOUNT_POINT/tmp/unit_results" ]; then
            sudo cp -a -n "$MOUNT_POINT/tmp/unit_results/." "$DEST_DIR/unit/" 2>/dev/null || true
        fi
        if [ -d "$MOUNT_POINT/tmp/fsx_results" ]; then
            sudo cp -a -n "$MOUNT_POINT/tmp/fsx_results/." "$DEST_DIR/fsx/" 2>/dev/null || true
        fi
        sudo umount "$MOUNT_POINT"
    fi
fi

# 3. Synchronize host-side serial logs and synthesize comprehensive exploit validation reports
HOST_RESULTS_DIR="${RESULTS_DIR:-$ENV_DIR/results}"
log_step "Consolidating security validation artifacts"
for test_pair in "copy-fail:copyfail" "dirty-frag:dirtyfrag" "fragnesia:fragnesia"; do
    tname="${test_pair%%:*}"
    tsuffix="${test_pair##*:}"

    for mode in off on; do
        slog="$HOST_RESULTS_DIR/sec_${tsuffix}_${mode}.log"
        if [ -f "$slog" ]; then
            cp -f "$slog" "$DEST_DIR/exploit/sec_${tsuffix}_${mode}.log" 2>/dev/null || true
            if [ ! -f "$DEST_DIR/exploit/${tname}_${mode}.log" ] || [ $(wc -c < "$DEST_DIR/exploit/${tname}_${mode}.log" 2>/dev/null || echo 0) -lt 200 ]; then
                cp -f "$slog" "$DEST_DIR/exploit/${tname}_${mode}.log" 2>/dev/null || true
            fi
        fi
    done
done

# If copy-fail.log only contains single-line killed notification, enrich with mitigation context
if [ -f "$DEST_DIR/exploit/copy-fail.log" ] && [ $(wc -l < "$DEST_DIR/exploit/copy-fail.log" 2>/dev/null || echo 0) -le 3 ]; then
    if [ -f "$DEST_DIR/exploit/copy-fail_on.log" ]; then
        cp -f "$DEST_DIR/exploit/copy-fail_on.log" "$DEST_DIR/exploit/copy-fail.log"
    fi
fi

# Generate formal A/B security evaluation summary table
if [ -f "$SCRIPT_DIR/analyze_sec.py" ]; then
    python3 "$SCRIPT_DIR/analyze_sec.py" > "$DEST_DIR/exploit/security_summary.txt" 2>&1 || true
fi

sudo chown -R "$(id -u):$(id -g)" "$DEST_DIR" 2>/dev/null || true

# Sync harvested benchmark JSONs directly to results/raw for parse_results.py
RAW_DIR="${RESULTS_DIR:-$ENV_DIR/results}/raw"
mkdir -p "$RAW_DIR"

# Clean up any stale flat JSONs in RAW_DIR if structured variant folders exist
if [ -d "$DEST_DIR/bench/raw" ]; then
    for vdir in "$DEST_DIR/bench/raw"/*; do
        if [ -d "$vdir" ]; then
            vname="$(basename "$vdir")"
            mkdir -p "$RAW_DIR/$vname"
            cp -a "$vdir/." "$RAW_DIR/$vname/" 2>/dev/null || true
        fi
    done
elif [ -d "$DEST_DIR/bench" ]; then
    for vdir in "$DEST_DIR/bench"/*; do
        if [ -d "$vdir" ] && [ "$(basename "$vdir")" != "raw" ]; then
            vname="$(basename "$vdir")"
            mkdir -p "$RAW_DIR/$vname"
            cp -a "$vdir/." "$RAW_DIR/$vname/" 2>/dev/null || true
        fi
    done
fi

sudo chown -R "$(id -u):$(id -g)" "$RAW_DIR" 2>/dev/null || true

BENCH_COUNT=$(find "$DEST_DIR/bench" -type f -name "*.json" 2>/dev/null | wc -l || echo 0)
EXPLOIT_COUNT=$(find "$DEST_DIR/exploit" -type f 2>/dev/null | wc -l || echo 0)
UNIT_COUNT=$(find "$DEST_DIR/unit" -type f 2>/dev/null | wc -l || echo 0)
FSX_COUNT=$(find "$DEST_DIR/fsx" -type f 2>/dev/null | wc -l || echo 0)

log_ok "Artifact extraction complete:"
log_kv "Benchmark JSONs" "$BENCH_COUNT files in $DEST_DIR/bench"
log_kv "Exploit Logs"    "$EXPLOIT_COUNT files in $DEST_DIR/exploit"
log_kv "Unit Test Logs"  "$UNIT_COUNT files in $DEST_DIR/unit"
log_kv "FSX Test Logs"   "$FSX_COUNT files in $DEST_DIR/fsx"
