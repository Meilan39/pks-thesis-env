#!/usr/bin/env bash
# scripts/data/fetch_results.sh - Extract benchmark & test artifacts from disk image or shared mount
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ENV_DIR/scripts/common.sh"

DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
DEST_DIR="${RESULTS_DIR:-$ENV_DIR/results}/raw"
mkdir -p "$DEST_DIR"

# If running directly inside VM or if /mnt/protected is mounted on host
if [ -d "/mnt/protected/bench_results" ]; then
    cp -a /mnt/protected/bench_results/. "$DEST_DIR/" 2>/dev/null || true
fi
if [ -d "/mnt/protected/exploit_results" ]; then
    cp -a /mnt/protected/exploit_results/. "$DEST_DIR/" 2>/dev/null || true
fi
if [ -d "/mnt/protected/unit_results" ]; then
    cp -a /mnt/protected/unit_results/. "$DEST_DIR/" 2>/dev/null || true
fi

# If disk image exists and losetup/mount available with permissions
if [ -f "$DISK_IMG" ] && command -v losetup >/dev/null 2>&1 && [ "${EUID:-$(id -u)}" -eq 0 ]; then
    LOOP=$(losetup --find --show --partscan "$DISK_IMG" 2>/dev/null || true)
    if [ -n "$LOOP" ]; then
        MOUNT_PT="$(mktemp -d)"
        if mount -o ro "${LOOP}p2" "$MOUNT_PT" 2>/dev/null; then
            [ -d "$MOUNT_PT/bench_results" ] && cp -a "$MOUNT_PT/bench_results/." "$DEST_DIR/" 2>/dev/null || true
            [ -d "$MOUNT_PT/exploit_results" ] && cp -a "$MOUNT_PT/exploit_results/." "$DEST_DIR/" 2>/dev/null || true
            [ -d "$MOUNT_PT/unit_results" ] && cp -a "$MOUNT_PT/unit_results/." "$DEST_DIR/" 2>/dev/null || true
            umount "$MOUNT_PT" 2>/dev/null || true
        fi
        losetup -d "$LOOP" 2>/dev/null || true
        rmdir "$MOUNT_PT" 2>/dev/null || true
    fi
fi

echo "[analyze-perf] Fetching telemetry artifacts from /mnt/protected... [DONE]"
