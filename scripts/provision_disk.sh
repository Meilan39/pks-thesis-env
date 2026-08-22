#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# Provision a persistent root filesystem image for PKS evaluation.
# Usage: ./provision_disk.sh [output_disk.img]
#
# The image will contain:
#   - Minimal Debian (or Ubuntu) rootfs
#   - build-essential, python3, git, sudo, fio, sysbench, etc.
#   - Non-root user 'testuser' (uid=1000)
#   - /exploit directory populated from guest-assets
# ----------------------------------------------------------------------

DISK_IMG="${1:-$HOME/src/env/images/disk.img}"
DISK_SIZE="${DISK_SIZE:-8G}"
MOUNT_POINT="$(mktemp -d)"
SUITE="${SUITE:-bookworm}"           # Debian release (or 'jammy' for Ubuntu)
ARCH="${ARCH:-amd64}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"

# Ensure required host tools exist
for cmd in qemu-img debootstrap mount umount chroot; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd not found. Install qemu-utils, debootstrap, util-linux."
        exit 1
    fi
done

echo "=== Creating disk image: $DISK_IMG ($DISK_SIZE) ==="
qemu-img create -f raw "$DISK_IMG" "$DISK_SIZE"

# Partition and format (single ext4 partition)
echo "=== Partitioning and formatting ==="
# Use sfdisk to create a single Linux partition
echo ';' | sfdisk "$DISK_IMG" >/dev/null 2>&1

# Find loop device and map partitions
LOOP=$(sudo losetup --find --show --partscan "$DISK_IMG")
PART="${LOOP}p1"

# Wait for partition to appear
sleep 1

# Format as ext4
sudo mkfs.ext4 -F "$PART"

# Mount the partition
sudo mount "$PART" "$MOUNT_POINT"

# Cleanup function
cleanup() {
    echo "=== Cleaning up ==="
    sudo umount "$MOUNT_POINT" || true
    sudo losetup -d "$LOOP" || true
    rmdir "$MOUNT_POINT" || true
}
trap cleanup EXIT

echo "=== Running debootstrap ($SUITE) ==="
sudo debootstrap --arch "$ARCH" "$SUITE" "$MOUNT_POINT" "$MIRROR"

# Prepare chroot environment
sudo mount --bind /dev "$MOUNT_POINT/dev"
sudo mount --bind /proc "$MOUNT_POINT/proc"
sudo mount --bind /sys "$MOUNT_POINT/sys"

# Copy resolv.conf for network
sudo cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"

# ----------------------------------------------
# Inside chroot: install packages, create user, copy assets
# ----------------------------------------------
echo "=== Installing packages inside chroot ==="
sudo chroot "$MOUNT_POINT" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
        build-essential \
        python3 \
        git \
        sudo \
        curl \
        wget \
        fio \
        sysbench \
        libcap-dev \
        libc6-dev \
        linux-image-amd64 \
        vim-tiny \
        net-tools \
        iproute2 \
        ca-certificates \
        gnupg \
        lsb-release \
        coreutils \
        psmisc \
        procps
    apt-get clean
"

# Create testuser (non-root)
echo "=== Creating testuser ==="
sudo chroot "$MOUNT_POINT" /bin/bash -c "
    useradd -m -s /bin/bash -u 1000 testuser
    echo 'testuser:testuser' | chpasswd
    echo 'testuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
"

# Copy guest-assets into /exploit inside the image
echo "=== Copying guest-assets to /exploit ==="
GUEST_ASSETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../guest-assets" && pwd)"
sudo mkdir -p "$MOUNT_POINT/exploit"
sudo cp -a "$GUEST_ASSETS_DIR/." "$MOUNT_POINT/exploit/"
sudo chown -R root:root "$MOUNT_POINT/exploit"
sudo chmod -R 755 "$MOUNT_POINT/exploit"

# Make sure run_tests.sh is executable
if [ -f "$MOUNT_POINT/exploit/run_tests.sh" ]; then
    sudo chmod +x "$MOUNT_POINT/exploit/run_tests.sh"
fi

# Unmount chroot mounts
sudo umount "$MOUNT_POINT/dev"
sudo umount "$MOUNT_POINT/proc"
sudo umount "$MOUNT_POINT/sys"

echo "=== Provisioning complete ==="
echo "Disk image: $DISK_IMG"
echo "You can now boot it with run_qemu_*.sh scripts."