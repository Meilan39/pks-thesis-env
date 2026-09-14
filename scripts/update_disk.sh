#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# update_disk.sh - Update /exploit inside the persistent disk image
# Usage: sudo ./update_disk.sh
# ----------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
GUEST_ASSETS_DIR="${GUEST_ASSETS_DIR:-$ENV_DIR/guest-assets}"

if [ ! -f "$DISK_IMG" ]; then
    echo "Error: Disk image not found at $DISK_IMG"
    exit 1
fi

if [ ! -d "$GUEST_ASSETS_DIR" ]; then
    echo "Error: Source guest-assets directory not found at $GUEST_ASSETS_DIR"
    exit 1
fi

echo "=== Updating guest assets in $DISK_IMG ==="

# Attach the image as a loop device with partition scanning
LOOP=$(sudo losetup --find --show --partscan "$DISK_IMG")
echo "Loop device: $LOOP"

# The root partition is ${LOOP}p1
ROOT_PART="${LOOP}p1"
if [ ! -b "$ROOT_PART" ]; then
    echo "Error: Partition $ROOT_PART not found. Is the image partitioned?"
    sudo losetup -d "$LOOP"
    exit 1
fi

# Mount it
MOUNT_POINT="$(mktemp -d)"
sudo mount "$ROOT_PART" "$MOUNT_POINT"

# Replace /exploit if present in guest-assets
if [ -d "$GUEST_ASSETS_DIR/exploit" ]; then
    echo "Syncing /exploit ..."
    sudo rm -rf "$MOUNT_POINT/exploit"
    sudo mkdir -p "$MOUNT_POINT/exploit"
    sudo cp -a "$GUEST_ASSETS_DIR/exploit/." "$MOUNT_POINT/exploit/"
    sudo chown -R root:root "$MOUNT_POINT/exploit"
    sudo chmod -R 755 "$MOUNT_POINT/exploit"
    if [ -f "$MOUNT_POINT/exploit/run_tests.sh" ]; then
        sudo chmod +x "$MOUNT_POINT/exploit/run_tests.sh"
    fi
fi

# Replace /benchmark if present in guest-assets
if [ -d "$GUEST_ASSETS_DIR/benchmark" ]; then
    echo "Syncing /benchmark ..."
    sudo rm -rf "$MOUNT_POINT/benchmark"
    sudo mkdir -p "$MOUNT_POINT/benchmark"
    sudo cp -a "$GUEST_ASSETS_DIR/benchmark/." "$MOUNT_POINT/benchmark/"
    sudo chown -R root:root "$MOUNT_POINT/benchmark"
    sudo chmod -R 755 "$MOUNT_POINT/benchmark"
    if [ -f "$MOUNT_POINT/benchmark/run_benchmarks.sh" ]; then
        sudo chmod +x "$MOUNT_POINT/benchmark/run_benchmarks.sh"
    fi
fi

# Ensure /mnt/protected mount point exists
sudo mkdir -p "$MOUNT_POINT/mnt/protected"

# Unmount and detach
sudo umount "$MOUNT_POINT"
sudo losetup -d "$LOOP"
rmdir "$MOUNT_POINT"

echo "=== Update complete ==="