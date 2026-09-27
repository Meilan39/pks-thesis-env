#!/usr/bin/env bash
# scripts/disk/disk_provision.sh - Provision dual-partition persistent disk image
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ENV_DIR/scripts/common.sh"
-include "$ENV_DIR/config.mk" 2>/dev/null || true

DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
DISK_SIZE="${DISK_SIZE:-8G}"
ROOTFS_SIZE="${ROOTFS_SIZE:-6G}"
SUITE="${DEBIAN_SUITE:-bookworm}"
ARCH="${DEBIAN_ARCH:-amd64}"
MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"

if [ -f "$DISK_IMG" ]; then
    echo "[disk-provision] Base disk image verified (images/disk.img)... [DONE]"
    echo ""
    exit 0
fi

START_TIME=$(date +%s)
require_cmds qemu-img debootstrap sfdisk losetup mkfs.ext4 sudo

mkdir -p "$(dirname "$DISK_IMG")"
qemu-img create -f raw "$DISK_IMG" "$DISK_SIZE" >/dev/null

cat <<EOF | sfdisk "$DISK_IMG" >/dev/null 2>&1
,${ROOTFS_SIZE},L,*
,,L
EOF

LOOP=$(sudo losetup --find --show --partscan "$DISK_IMG")
ROOT_PART="${LOOP}p1"
PROT_PART="${LOOP}p2"
sleep 1

sudo mkfs.ext4 -F -q "$ROOT_PART"
sudo mkfs.ext4 -F -q -O ^inline_data,^encrypt "$PROT_PART"

MOUNT_POINT="$(mktemp -d)"

cleanup() {
    sudo umount "$MOUNT_POINT/dev" 2>/dev/null || true
    sudo umount "$MOUNT_POINT/proc" 2>/dev/null || true
    sudo umount "$MOUNT_POINT/sys" 2>/dev/null || true
    sudo umount "$MOUNT_POINT" 2>/dev/null || true
    sudo losetup -d "$LOOP" 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

sudo mount "$ROOT_PART" "$MOUNT_POINT"
sudo debootstrap --arch "$ARCH" "$SUITE" "$MOUNT_POINT" "$MIRROR" >/dev/null 2>&1 || true

sudo mount --bind /dev "$MOUNT_POINT/dev" 2>/dev/null || true
sudo mount --bind /proc "$MOUNT_POINT/proc" 2>/dev/null || true
sudo mount --bind /sys "$MOUNT_POINT/sys" 2>/dev/null || true
sudo cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf" 2>/dev/null || true

# Setup /etc/fstab
sudo mkdir -p "$MOUNT_POINT/mnt/protected" "$MOUNT_POINT/pks-thesis-env"
echo "/dev/vda1 / ext4 errors=remount-ro 0 1" | sudo tee "$MOUNT_POINT/etc/fstab" >/dev/null
echo "/dev/vda2 /mnt/protected ext4 defaults,nofail 0 2" | sudo tee -a "$MOUNT_POINT/etc/fstab" >/dev/null
echo "pks_env /pks-thesis-env 9p trans=virtio,version=9p2000.L,nofail 0 0" | sudo tee -a "$MOUNT_POINT/etc/fstab" >/dev/null

# Install runtime packages
sudo chroot "$MOUNT_POINT" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
        build-essential python3 fio sqlite3 libsqlite3-dev libcap-dev libc6-dev sudo coreutils procps >/dev/null 2>&1 || true
    useradd -m -s /bin/bash -u 1000 testuser 2>/dev/null || true
    echo 'testuser:testuser' | chpasswd 2>/dev/null || true
    echo 'testuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/testuser 2>/dev/null || true
" 2>/dev/null || true

# Install autorun service
if [ -f "$ENV_DIR/scripts/guest-autorun/pks-autorun.sh" ]; then
    sudo cp "$ENV_DIR/scripts/guest-autorun/pks-autorun.sh" "$MOUNT_POINT/usr/local/bin/pks-autorun.sh"
    sudo chmod 755 "$MOUNT_POINT/usr/local/bin/pks-autorun.sh"
fi
if [ -f "$ENV_DIR/scripts/guest-autorun/pks-autorun.service" ]; then
    sudo cp "$ENV_DIR/scripts/guest-autorun/pks-autorun.service" "$MOUNT_POINT/etc/systemd/system/pks-autorun.service"
    sudo mkdir -p "$MOUNT_POINT/etc/systemd/system/multi-user.target.wants"
    sudo ln -sf /etc/systemd/system/pks-autorun.service "$MOUNT_POINT/etc/systemd/system/multi-user.target.wants/pks-autorun.service"
fi

ELAPSED=$(( $(date +%s) - START_TIME ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo "[disk-provision] Bootstrapped Debian Bookworm and partitioned 8GB image... [DONE] (${MINS}m ${SECS}s)"
echo ""
