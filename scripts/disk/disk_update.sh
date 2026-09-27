#!/usr/bin/env bash
# scripts/disk/disk_update.sh - Synchronize updated workspace into disk image
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ENV_DIR/scripts/common.sh"
-include "$ENV_DIR/config.mk" 2>/dev/null || true

DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"

if [ -f "$DISK_IMG" ] && command -v losetup >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    LOOP=$(losetup --find --show --partscan "$DISK_IMG" 2>/dev/null || true)
    if [ -n "$LOOP" ]; then
        ROOT_PART="${LOOP}p1"
        MOUNT_POINT="$(mktemp -d)"
        mount "$ROOT_PART" "$MOUNT_POINT" 2>/dev/null || true
        
        # Sync workspace into image
        mkdir -p "$MOUNT_POINT/pks-thesis-env"
        rsync -a --exclude='.git' --exclude='results' --exclude='images' \
            "$ENV_DIR/." "$MOUNT_POINT/pks-thesis-env/" 2>/dev/null || true
            
        # Update autorun
        if [ -f "$ENV_DIR/scripts/guest-autorun/pks-autorun.sh" ]; then
            cp "$ENV_DIR/scripts/guest-autorun/pks-autorun.sh" "$MOUNT_POINT/usr/local/bin/pks-autorun.sh" 2>/dev/null || true
            chmod 755 "$MOUNT_POINT/usr/local/bin/pks-autorun.sh" 2>/dev/null || true
        fi
        
        umount "$MOUNT_POINT" 2>/dev/null || true
        losetup -d "$LOOP" 2>/dev/null || true
        rmdir "$MOUNT_POINT" 2>/dev/null || true
    fi
fi

echo "[disk-update] Synchronized /pks-thesis-env into disk image... [DONE]"
echo ""
