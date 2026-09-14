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

mkdir -p "$DEST_DIR/bench" "$DEST_DIR/exploit"

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
        sudo umount "$MOUNT_POINT"
    fi
fi

# 2. Check rootfs /tmp if files were left in root partition
if [ -b "$ROOT_PART" ]; then
    log_step "Inspecting rootfs partition ($ROOT_PART)"
    if sudo mount -o ro "$ROOT_PART" "$MOUNT_POINT" 2>/dev/null; then
        if [ -d "$MOUNT_POINT/tmp/bench_results" ]; then
            sudo cp -a "$MOUNT_POINT/tmp/bench_results/." "$DEST_DIR/bench/" 2>/dev/null || true
        fi
        if [ -d "$MOUNT_POINT/tmp/exploit_results" ]; then
            sudo cp -a "$MOUNT_POINT/tmp/exploit_results/." "$DEST_DIR/exploit/" 2>/dev/null || true
        fi
        sudo umount "$MOUNT_POINT"
    fi
fi

sudo chown -R "$(id -u):$(id -g)" "$DEST_DIR" 2>/dev/null || true

BENCH_COUNT=$(find "$DEST_DIR/bench" -type f -name "*.json" 2>/dev/null | wc -l || echo 0)
EXPLOIT_COUNT=$(find "$DEST_DIR/exploit" -type f 2>/dev/null | wc -l || echo 0)

log_ok "Artifact extraction complete:"
log_kv "Benchmark JSONs" "$BENCH_COUNT files in $DEST_DIR/bench"
log_kv "Exploit Logs"    "$EXPLOIT_COUNT files in $DEST_DIR/exploit"
