#!/usr/bin/env bash
# ==============================================================================
# disk/run.sh - Provision the guest image (once), else refresh it
# ==============================================================================
# The workspace is shared live over virtio-9p, so workspace edits need no disk
# rebuild. autorun.sh is copied into the rootfs because it runs before 9p mounts.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

DISK_IMG="${DISK_IMG:-$REPO_ROOT/images/disk.img}"
DISK_SIZE="${DISK_SIZE:-8G}"
ROOTFS_SIZE="${ROOTFS_SIZE:-6G}"
SUITE="${DEBIAN_SUITE:-bookworm}"
ARCH="${DEBIAN_ARCH:-amd64}"
MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
RAW_LOG="$SCRIPT_DIR/raw.log"

mkdir -p "$REPO_ROOT/images"

# Required guest packages: compilers, fio, sqlite3, and test utilities.
PACKAGES="build-essential python3 fio sqlite3 libsqlite3-dev libcap-dev libc6-dev sudo coreutils procps"

# ------------------------------------------------------------------------------
# Helpers: virtual filesystems & chroot
# ------------------------------------------------------------------------------
mount_chroot_binds() {
    local mount_point="$1"
    for dir in dev proc sys; do
        sudo mount --bind "/$dir" "$mount_point/$dir" 2>/dev/null || true
    done
    sudo cp /etc/resolv.conf "$mount_point/etc/resolv.conf" 2>/dev/null || true
}

unmount_chroot_binds() {
    local mount_point="$1"
    for dir in dev proc sys; do
        sudo umount "$mount_point/$dir" 2>/dev/null || true
    done
}

install_packages() {
    local mount_point="$1"
    mount_chroot_binds "$mount_point"

    sudo chroot "$mount_point" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends $PACKAGES
        useradd -m -s /bin/bash -u 1000 testuser 2>/dev/null || true
        echo 'testuser:testuser' | chpasswd 2>/dev/null || true
        echo 'testuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/testuser
    "
    local status=$?
    unmount_chroot_binds "$mount_point"
    return "$status"
}

install_autorun() {
    local mount_point="$1"
    sudo cp "$REPO_ROOT/guest/autorun.sh" "$mount_point/usr/local/bin/pks-autorun.sh"
    sudo chmod 755 "$mount_point/usr/local/bin/pks-autorun.sh"
    sudo cp "$REPO_ROOT/guest/autorun.service" "$mount_point/etc/systemd/system/pks-autorun.service"
    sudo mkdir -p "$mount_point/etc/systemd/system/multi-user.target.wants"
    sudo ln -sf /etc/systemd/system/pks-autorun.service \
        "$mount_point/etc/systemd/system/multi-user.target.wants/pks-autorun.service"
}

# ------------------------------------------------------------------------------
# Provisioning & refresh pipelines
# ------------------------------------------------------------------------------
provision() {
    require_cmds qemu-img debootstrap sfdisk losetup mkfs.ext4 sudo

    qemu-img create -f raw "$DISK_IMG" "$DISK_SIZE"
    printf ',%s,L,*\n,,L\n' "$ROOTFS_SIZE" | sfdisk "$DISK_IMG"

    local loop_device
    loop_device=$(sudo losetup --find --show --partscan "$DISK_IMG")
    sleep 1

    sudo mkfs.ext4 -F -q "${loop_device}p1"
    sudo mkfs.ext4 -F -q -O ^inline_data,^encrypt "${loop_device}p2"

    local mount_point
    mount_point="$(mktemp -d)"

    cleanup() {
        unmount_chroot_binds "$mount_point"
        sudo umount "$mount_point" 2>/dev/null || true
        sudo losetup -d "$loop_device" 2>/dev/null || true
        rmdir "$mount_point" 2>/dev/null || true
    }
    trap cleanup RETURN

    sudo mount "${loop_device}p1" "$mount_point"
    sudo debootstrap --arch "$ARCH" "$SUITE" "$mount_point" "$MIRROR"
    sudo mkdir -p "$mount_point/mnt/protected" "$mount_point/pks-thesis-env"

    sudo tee "$mount_point/etc/fstab" >/dev/null <<FSTAB
/dev/vda1 / ext4 errors=remount-ro 0 1
/dev/vda2 /mnt/protected ext4 noauto,nofail 0 2
pks_env /pks-thesis-env 9p trans=virtio,version=9p2000.L,nofail 0 0
FSTAB

    install_packages "$mount_point"
    install_autorun "$mount_point"
}

refresh_image() {
    command -v losetup >/dev/null 2>&1 || {
        echo "losetup utility is missing"
        return 1
    }

    local loop_device
    loop_device=$(sudo losetup --find --show --partscan "$DISK_IMG") || return 1
    sleep 1

    local mount_point
    mount_point="$(mktemp -d)"
    local rc=0

    if sudo mount "${loop_device}p1" "$mount_point"; then
        install_packages "$mount_point" || echo "[disk] WARN: package refresh failed (offline?); some benchmark tools may be unavailable"
        install_autorun "$mount_point" || rc=1

        # Verify autorun installation marker
        if ! sudo grep -q 'HB autorun:' "$mount_point/usr/local/bin/pks-autorun.sh" 2>/dev/null; then
            echo "autorun marker not found after installation"
            rc=1
        fi

        sudo umount "$mount_point" 2>/dev/null || true
    else
        rc=1
    fi

    sudo losetup -d "$loop_device" 2>/dev/null || true
    rmdir "$mount_point" 2>/dev/null || true
    return "$rc"
}

# ------------------------------------------------------------------------------
# Execution dispatch
# ------------------------------------------------------------------------------
if [ ! -f "$DISK_IMG" ]; then
    log_info "[disk] provisioning $SUITE image (one-time, initial setup)..."
    start_time=$(date +%s)
    provision >> "$RAW_LOG" 2>&1
    elapsed=$(( $(date +%s) - start_time ))
    log_done "[disk] provisioned in ${elapsed}s"
    image_size="$(du -h "$DISK_IMG" 2>/dev/null | cut -f1)"
    emit_status disk all PASS provisioned=yes image="$image_size" | tee "$SCRIPT_DIR/result.log"
else
    log_done "[disk] image present; refreshing packages and autorun service."
    image_size="$(du -h "$DISK_IMG" 2>/dev/null | cut -f1)"
    if refresh_image >> "$RAW_LOG" 2>&1; then
        emit_status disk all PASS refreshed=yes image="$image_size" | tee "$SCRIPT_DIR/result.log"
    else
        emit_status disk all FAIL note=refresh_failed image="$image_size" | tee "$SCRIPT_DIR/result.log"
        die "image refresh failed; see $RAW_LOG"
    fi
fi

