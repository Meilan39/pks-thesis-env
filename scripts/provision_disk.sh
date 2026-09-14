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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISK_IMG="${1:-$ENV_DIR/images/disk.img}"
DISK_SIZE="${DISK_SIZE:-8G}"
MOUNT_POINT="$(mktemp -d)"
SUITE="${SUITE:-bookworm}"           # Debian release (or 'jammy' for Ubuntu)
ARCH="${ARCH:-amd64}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"

# Ensure required host tools exist
for cmd in qemu-img debootstrap mount umount chroot sfdisk losetup mkfs.ext4; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd not found. Install qemu-utils, debootstrap, util-linux, e2fsprogs."
        exit 1
    fi
done

echo "=== Creating disk image: $DISK_IMG ($DISK_SIZE) ==="
mkdir -p "$(dirname "$DISK_IMG")"
qemu-img create -f raw "$DISK_IMG" "$DISK_SIZE"

# Partition into Rootfs (6GB) and Protected Storage (2GB)
echo "=== Partitioning disk image ==="
cat <<EOF | sfdisk "$DISK_IMG" >/dev/null 2>&1
,6G,L,*
,,L
EOF

# Find loop device and map partitions
LOOP=$(sudo losetup --find --show --partscan "$DISK_IMG")
ROOT_PART="${LOOP}p1"
PROT_PART="${LOOP}p2"

# Wait for partitions to appear
sleep 1

# Format root partition as standard ext4
sudo mkfs.ext4 -F "$ROOT_PART"
# Format protected partition without inline_data or encryption
sudo mkfs.ext4 -F -O ^inline_data,^encrypt "$PROT_PART"

# Mount the root partition
sudo mount "$ROOT_PART" "$MOUNT_POINT"

# Cleanup function
cleanup() {
    echo "=== Cleaning up ==="
    sudo umount "$MOUNT_POINT/dev" 2>/dev/null || true
    sudo umount "$MOUNT_POINT/proc" 2>/dev/null || true
    sudo umount "$MOUNT_POINT/sys" 2>/dev/null || true
    sudo umount "$MOUNT_POINT" 2>/dev/null || true
    sudo losetup -d "$LOOP" 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
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

# Create mount point for protected filesystem
sudo mkdir -p "$MOUNT_POINT/mnt/protected"

# Set up /etc/fstab with nofail for protected partition
echo "/dev/vda1 / ext4 errors=remount-ro 0 1" | sudo tee "$MOUNT_POINT/etc/fstab"
echo "/dev/vda2 /mnt/protected ext4 defaults,nofail 0 2" | sudo tee -a "$MOUNT_POINT/etc/fstab"

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

# Copy guest-assets into /exploit and /benchmark inside the image
echo "=== Copying guest-assets ==="
GUEST_ASSETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../guest-assets" && pwd)"
sudo mkdir -p "$MOUNT_POINT/exploit" "$MOUNT_POINT/benchmark"
if [ -d "$GUEST_ASSETS_DIR/exploit" ]; then
    sudo cp -a "$GUEST_ASSETS_DIR/exploit/." "$MOUNT_POINT/exploit/"
fi
if [ -d "$GUEST_ASSETS_DIR/benchmark" ]; then
    sudo cp -a "$GUEST_ASSETS_DIR/benchmark/." "$MOUNT_POINT/benchmark/"
fi
sudo chown -R root:root "$MOUNT_POINT/exploit" "$MOUNT_POINT/benchmark"
sudo chmod -R 755 "$MOUNT_POINT/exploit" "$MOUNT_POINT/benchmark"

# Make sure runner scripts are executable
if [ -f "$MOUNT_POINT/exploit/run_tests.sh" ]; then
    sudo chmod +x "$MOUNT_POINT/exploit/run_tests.sh"
fi
if [ -f "$MOUNT_POINT/benchmark/run_benchmarks.sh" ]; then
    sudo chmod +x "$MOUNT_POINT/benchmark/run_benchmarks.sh"
fi

# Compile dirty-frag inside chroot if exp.c is present
if [ -f "$MOUNT_POINT/exploit/dirty-frag/exp.c" ]; then
    echo "=== Compiling dirty-frag harness inside chroot ==="
    sudo chroot "$MOUNT_POINT" /bin/bash -c "
        cd /exploit/dirty-frag && gcc -O0 -Wall -o exp exp.c -lutil
    " || echo "WARN: dirty-frag compilation failed inside chroot"
fi

# Unmount chroot mounts
sudo umount "$MOUNT_POINT/dev"
sudo umount "$MOUNT_POINT/proc"
sudo umount "$MOUNT_POINT/sys"

echo "=== Provisioning complete ==="
echo "Disk image: $DISK_IMG"
echo "You can now boot it with run_qemu_*.sh scripts."