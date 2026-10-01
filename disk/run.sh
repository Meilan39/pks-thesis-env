#!/usr/bin/env bash
# disk/run.sh - Provision the persistent guest image (ONCE; debootstrap is slow
# and gains nothing from re-runs) and, on every invocation, refresh the two
# things that DO change: the required package set and the in-guest autorun
# service. The workspace itself is shared live over virtio-9p, so there is no
# workspace rsync step - only the autorun script, which must live in the image
# because it runs before the 9p mount.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/.." && pwd)"
source "$ROOT/common.sh"

DISK_IMG="${DISK_IMG:-$ROOT/images/disk.img}"
DISK_SIZE="${DISK_SIZE:-8G}"; ROOTFS_SIZE="${ROOTFS_SIZE:-6G}"
SUITE="${DEBIAN_SUITE:-bookworm}"; ARCH="${DEBIAN_ARCH:-amd64}"
MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
RAW="$DIR/raw.log"; mkdir -p "$ROOT/images"

# perl provides prove (pjd); the rest are compilers + benchmark tools.
PACKAGES="build-essential python3 perl libtest-harness-perl fio sqlite3 libsqlite3-dev libcap-dev libc6-dev sudo coreutils procps"

# install_packages <mounted-root> - idempotent apt install inside the image.
# Needs dev/proc/sys binds + resolv.conf for the chroot's apt to work.
install_packages() {
    local mp="$1" d
    for d in dev proc sys; do sudo mount --bind "/$d" "$mp/$d" 2>/dev/null || true; done
    sudo cp /etc/resolv.conf "$mp/etc/resolv.conf" 2>/dev/null || true
    sudo chroot "$mp" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends $PACKAGES
        useradd -m -s /bin/bash -u 1000 testuser 2>/dev/null || true
        echo 'testuser:testuser' | chpasswd 2>/dev/null || true
        echo 'testuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/testuser
    "
    local st=$?
    for d in dev proc sys; do sudo umount "$mp/$d" 2>/dev/null || true; done
    return $st
}

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
    sudo mkdir -p "$mp/mnt/protected" "$mp/pks-thesis-env"
    sudo tee "$mp/etc/fstab" >/dev/null <<FSTAB
/dev/vda1 / ext4 errors=remount-ro 0 1
/dev/vda2 /mnt/protected ext4 noauto,nofail 0 2
pks_env /pks-thesis-env 9p trans=virtio,version=9p2000.L,nofail 0 0
FSTAB
    install_packages "$mp"
    install_autorun "$mp"
}

# Refresh packages + autorun in an existing image, verifying the new autorun
# landed. Package install is best-effort (a network/apt hiccup should not fail
# the run), but autorun must succeed. Returns nonzero only on autorun failure.
refresh_image() {
    command -v losetup >/dev/null 2>&1 || { echo "losetup missing"; return 1; }
    local loop mp rc=0
    loop=$(sudo losetup --find --show --partscan "$DISK_IMG") || return 1
    sleep 1; mp="$(mktemp -d)"
    if sudo mount "${loop}p1" "$mp"; then
        install_packages "$mp" || echo "[disk] WARN: package refresh failed (offline?); pjd/prove may be unavailable"
        install_autorun "$mp" || rc=1
        sudo grep -q 'HB autorun:' "$mp/usr/local/bin/pks-autorun.sh" 2>/dev/null || { echo "autorun marker not found after install"; rc=1; }
        sudo umount "$mp" 2>/dev/null || true
    else
        rc=1
    fi
    sudo losetup -d "$loop" 2>/dev/null || true; rmdir "$mp" 2>/dev/null || true
    return $rc
}

if [ ! -f "$DISK_IMG" ]; then
    log_info "[disk] provisioning $SUITE image (one-time, slow)..."
    start=$(date +%s)
    provision >> "$RAW" 2>&1            # set -e aborts loudly on real failure
    log_done "[disk] provisioned in $(( $(date +%s) - start ))s"
    emit_status disk all PASS provisioned=yes image="$(du -h "$DISK_IMG" 2>/dev/null | cut -f1)" | tee "$DIR/result.log"
else
    log_done "[disk] image present; refreshing packages + autorun."
    if refresh_image >> "$RAW" 2>&1; then
        emit_status disk all PASS refreshed=yes image="$(du -h "$DISK_IMG" 2>/dev/null | cut -f1)" | tee "$DIR/result.log"
    else
        emit_status disk all FAIL note=refresh_failed image="$(du -h "$DISK_IMG" 2>/dev/null | cut -f1)" | tee "$DIR/result.log"
        die "image refresh failed; see $RAW"
    fi
fi
