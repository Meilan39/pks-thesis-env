#!/usr/bin/env bash
# disk/run.sh - Provision the persistent guest image (ONCE; skipped if it
# already exists, since debootstrap is slow and gains nothing from re-runs) and
# (re)install the in-guest autorun service. The workspace itself is shared live
# over virtio-9p, so there is no workspace rsync step - only the autorun script,
# which must live in the image because it runs before the 9p mount.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/.." && pwd)"
source "$ROOT/common.sh"

DISK_IMG="${DISK_IMG:-$ROOT/images/disk.img}"
DISK_SIZE="${DISK_SIZE:-8G}"; ROOTFS_SIZE="${ROOTFS_SIZE:-6G}"
SUITE="${DEBIAN_SUITE:-bookworm}"; ARCH="${DEBIAN_ARCH:-amd64}"
MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
RAW="$ROOT/results/raw/disk.log"; mkdir -p "$(dirname "$RAW")" "$ROOT/images"

install_autorun() {  # $1 = mounted root
    sudo cp "$ROOT/guest/autorun.sh" "$1/usr/local/bin/pks-autorun.sh"
    sudo chmod 755 "$1/usr/local/bin/pks-autorun.sh"
    sudo cp "$ROOT/guest/autorun.service" "$1/etc/systemd/system/pks-autorun.service"
    sudo mkdir -p "$1/etc/systemd/system/multi-user.target.wants"
    sudo ln -sf /etc/systemd/system/pks-autorun.service \
        "$1/etc/systemd/system/multi-user.target.wants/pks-autorun.service"
}

provision() {
    require_cmds qemu-img debootstrap sfdisk losetup mkfs.ext4 sudo
    qemu-img create -f raw "$DISK_IMG" "$DISK_SIZE"
    printf ',%s,L,*\n,,L\n' "$ROOTFS_SIZE" | sfdisk "$DISK_IMG"

    local loop mp
    loop=$(sudo losetup --find --show --partscan "$DISK_IMG"); sleep 1
    sudo mkfs.ext4 -F -q "${loop}p1"
    sudo mkfs.ext4 -F -q -O ^inline_data,^encrypt "${loop}p2"

    mp="$(mktemp -d)"
    cleanup() { for d in dev proc sys ""; do sudo umount "$mp/$d" 2>/dev/null || true; done
                sudo losetup -d "$loop" 2>/dev/null || true; rmdir "$mp" 2>/dev/null || true; }
    trap cleanup RETURN

    sudo mount "${loop}p1" "$mp"
    sudo debootstrap --arch "$ARCH" "$SUITE" "$mp" "$MIRROR"
    for d in dev proc sys; do sudo mount --bind "/$d" "$mp/$d"; done
    sudo cp /etc/resolv.conf "$mp/etc/resolv.conf" 2>/dev/null || true

    sudo mkdir -p "$mp/mnt/protected" "$mp/pks-thesis-env"
    sudo tee "$mp/etc/fstab" >/dev/null <<FSTAB
/dev/vda1 / ext4 errors=remount-ro 0 1
/dev/vda2 /mnt/protected ext4 defaults,nofail 0 2
pks_env /pks-thesis-env 9p trans=virtio,version=9p2000.L,nofail 0 0
FSTAB

    sudo chroot "$mp" /bin/bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends \
            build-essential python3 fio sqlite3 libsqlite3-dev libcap-dev libc6-dev \
            perl sudo coreutils procps
        useradd -m -s /bin/bash -u 1000 testuser 2>/dev/null || true
        echo "testuser:testuser" | chpasswd 2>/dev/null || true
        echo "testuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/testuser
    '
    install_autorun "$mp"
}

if [ ! -f "$DISK_IMG" ]; then
    log_info "[disk] provisioning $SUITE image (one-time, slow)..."
    start=$(date +%s)
    provision >> "$RAW" 2>&1
    log_done "[disk] provisioned in $(( $(date +%s) - start ))s"
else
    log_done "[disk] image present; refreshing autorun only."
    if command -v losetup >/dev/null 2>&1; then
        loop=$(sudo losetup --find --show --partscan "$DISK_IMG"); sleep 1
        mp="$(mktemp -d)"; sudo mount "${loop}p1" "$mp"
        install_autorun "$mp" >> "$RAW" 2>&1 || true
        sudo umount "$mp" 2>/dev/null || true; sudo losetup -d "$loop" 2>/dev/null || true; rmdir "$mp" 2>/dev/null || true
    fi
fi

emit_status disk all PASS image="$(du -h "$DISK_IMG" 2>/dev/null | cut -f1)" | tee "$DIR/result.log"
