#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# update_disk.sh - Update /exploit inside the persistent disk image
# Usage: sudo ./update_disk.sh
# ----------------------------------------------------------------------

if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

DISK_IMG="${DISK_IMG:-$USER_HOME/src/env/images/disk.img}"
SOURCE_EXPLOIT="${SOURCE_EXPLOIT:-$USER_HOME/src/env/guest-assets/exploit}"

if [ ! -f "$DISK_IMG" ]; then
    echo "Error: Disk image not found at $DISK_IMG"
    exit 1
fi

if [ ! -d "$SOURCE_EXPLOIT" ]; then
    echo "Error: Source exploit directory not found at $SOURCE_EXPLOIT"
    exit 1
fi

echo "=== Updating /exploit in $DISK_IMG ==="

# Attach the image as a loop device with partition scanning
LOOP=$(sudo losetup --find --show --partscan "$DISK_IMG")
echo "Loop device: $LOOP"

# The root partition is usually ${LOOP}p1
ROOT_PART="${LOOP}p1"
if [ ! -b "$ROOT_PART" ]; then
    echo "Error: Partition $ROOT_PART not found. Is the image partitioned?"
    sudo losetup -d "$LOOP"
    exit 1
fi

# Mount it
MOUNT_POINT="$(mktemp -d)"
sudo mount "$ROOT_PART" "$MOUNT_POINT"

# Replace /exploit
echo "Removing old /exploit ..."
sudo rm -rf "$MOUNT_POINT/exploit"

echo "Copying new exploit suite ..."
sudo cp -a "$SOURCE_EXPLOIT" "$MOUNT_POINT/exploit"
sudo chown -R root:root "$MOUNT_POINT/exploit"
sudo chmod -R 755 "$MOUNT_POINT/exploit"
# Make run_tests.sh executable
if [ -f "$MOUNT_POINT/exploit/run_tests.sh" ]; then
    sudo chmod +x "$MOUNT_POINT/exploit/run_tests.sh"
fi

# Unmount and detach
sudo umount "$MOUNT_POINT"
sudo losetup -d "$LOOP"
rmdir "$MOUNT_POINT"

echo "=== Update complete ==="