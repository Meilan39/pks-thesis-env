#!/usr/bin/env bash
# scripts/data/fetch_results.sh - Extract benchmark & test artifacts from disk image or shared mount
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ENV_DIR/scripts/common.sh"

DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
DEST_DIR="${RESULTS_DIR:-$ENV_DIR/results}/raw"
mkdir -p "$DEST_DIR"

copy_results() {
    local src="$1"
    for dir in bench_results exploit_results unit_results; do
        [ -d "$src/$dir" ] && cp -a "$src/$dir/." "$DEST_DIR/" 2>/dev/null || true
    done
}

# 1. From guest mount
copy_results "/mnt/protected"

# 2. From raw disk image loopback mount if running on host with root
if [ -f "$DISK_IMG" ] && command -v losetup >/dev/null 2>&1 && [ "${EUID:-$(id -u)}" -eq 0 ]; then
    LOOP=$(losetup --find --show --partscan "$DISK_IMG" 2>/dev/null || true)
    if [ -n "$LOOP" ]; then
        MOUNT_PT="$(mktemp -d)"
        if mount -o ro "${LOOP}p2" "$MOUNT_PT" 2>/dev/null; then
            copy_results "$MOUNT_PT"
            umount "$MOUNT_PT" 2>/dev/null || true
        fi
        losetup -d "$LOOP" 2>/dev/null || true
        rmdir "$MOUNT_PT" 2>/dev/null || true
    fi
fi

echo "[analyze-perf] Fetching telemetry artifacts from /mnt/protected... [DONE]"
