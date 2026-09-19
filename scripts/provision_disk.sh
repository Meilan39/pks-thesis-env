#!/usr/bin/env bash
# ==============================================================================
# scripts/provision_disk.sh - Provision dual-partition persistent disk image
# ==============================================================================
# Usage: ./provision_disk.sh [output_disk.img]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISK_IMG="${1:-${DISK_IMG:-$ENV_DIR/images/disk.img}}"
DISK_SIZE="${DISK_SIZE:-8G}"
ROOTFS_SIZE="${ROOTFS_SIZE:-6G}"
SUITE="${DEBIAN_SUITE:-bookworm}"
ARCH="${DEBIAN_ARCH:-amd64}"
MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
GUEST_ASSETS_DIR="${GUEST_ASSETS_DIR:-$ENV_DIR/guest-assets}"

require_cmds qemu-img debootstrap mount umount chroot sfdisk losetup mkfs.ext4 sudo tee

log_header "Provisioning Persistent Disk Image"
log_kv "Output Image" "$DISK_IMG"
log_kv "Total Size"   "$DISK_SIZE"
log_kv "Rootfs Size"  "$ROOTFS_SIZE"
log_kv "Suite"        "$SUITE ($ARCH)"
log_kv "Mirror"       "$MIRROR"

mkdir -p "$(dirname "$DISK_IMG")"
log_step "Creating raw disk container: $DISK_IMG ($DISK_SIZE)"
qemu-img create -f raw "$DISK_IMG" "$DISK_SIZE" >/dev/null

log_step "Partitioning disk into rootfs (${ROOTFS_SIZE}) and protected partition"
cat <<EOF | sfdisk "$DISK_IMG" >/dev/null 2>&1
,${ROOTFS_SIZE},L,*
,,L
EOF

log_step "Attaching loop device with partition scanning"
LOOP=$(sudo losetup --find --show --partscan "$DISK_IMG")
ROOT_PART="${LOOP}p1"
PROT_PART="${LOOP}p2"

# Ensure partitions are settled
sleep 1
[ -b "$ROOT_PART" ] || die "Root partition $ROOT_PART not detected"
[ -b "$PROT_PART" ] || die "Protected partition $PROT_PART not detected"

log_step "Formatting root partition ($ROOT_PART) as ext4"
sudo mkfs.ext4 -F -q "$ROOT_PART"

log_step "Formatting protected partition ($PROT_PART) as ext4 (no inline_data, no encrypt)"
sudo mkfs.ext4 -F -q -O ^inline_data,^encrypt "$PROT_PART"

MOUNT_POINT="$(mktemp -d)"

cleanup() {
    log_step "Cleaning up loop devices and temporary mounts"
    sudo umount "$MOUNT_POINT/dev" 2>/dev/null || true
    sudo umount "$MOUNT_POINT/proc" 2>/dev/null || true
    sudo umount "$MOUNT_POINT/sys" 2>/dev/null || true
    sudo umount "$MOUNT_POINT" 2>/dev/null || true
    sudo losetup -d "$LOOP" 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

sudo mount "$ROOT_PART" "$MOUNT_POINT"

log_step "Bootstrapping minimal Debian system ($SUITE)"
sudo debootstrap --arch "$ARCH" "$SUITE" "$MOUNT_POINT" "$MIRROR"

# Prepare chroot mounts
sudo mount --bind /dev "$MOUNT_POINT/dev"
sudo mount --bind /proc "$MOUNT_POINT/proc"
sudo mount --bind /sys "$MOUNT_POINT/sys"

# Configure DNS resolution
sudo cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf" 2>/dev/null || true

# Setup persistent mount table (/etc/fstab)
log_step "Configuring /etc/fstab with persistent mount points"
sudo mkdir -p "$MOUNT_POINT/mnt/protected"
echo "/dev/vda1 / ext4 errors=remount-ro 0 1" | sudo tee "$MOUNT_POINT/etc/fstab" >/dev/null
echo "/dev/vda2 /mnt/protected ext4 defaults,nofail 0 2" | sudo tee -a "$MOUNT_POINT/etc/fstab" >/dev/null

log_step "Installing evaluation packages inside chroot"
sudo chroot "$MOUNT_POINT" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
        build-essential \
        python3 \
        git \
        sudo \
        curl \
        wget \
        fio \
        sysbench \
        sqlite3 \
        libsqlite3-dev \
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

log_step "Creating unprivileged evaluation user 'testuser'"
sudo chroot "$MOUNT_POINT" /bin/bash -c "
    useradd -m -s /bin/bash -u 1000 testuser 2>/dev/null || true
    echo 'testuser:testuser' | chpasswd
    echo 'testuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/testuser
    chmod 0440 /etc/sudoers.d/testuser
"

log_step "Populating guest assets and test harnesses"
sudo mkdir -p "$MOUNT_POINT/exploit" "$MOUNT_POINT/benchmark" "$MOUNT_POINT/unit-tests" "$MOUNT_POINT/fsx" "$MOUNT_POINT/pjdfstest"
if [ -d "$GUEST_ASSETS_DIR/exploit" ]; then
    sudo cp -a "$GUEST_ASSETS_DIR/exploit/." "$MOUNT_POINT/exploit/"
fi
if [ -d "$GUEST_ASSETS_DIR/benchmark" ]; then
    sudo cp -a "$GUEST_ASSETS_DIR/benchmark/." "$MOUNT_POINT/benchmark/"
fi
if [ -d "$GUEST_ASSETS_DIR/unit-tests" ]; then
    sudo cp -a "$GUEST_ASSETS_DIR/unit-tests/." "$MOUNT_POINT/unit-tests/"
fi
if [ -d "$GUEST_ASSETS_DIR/fsx" ]; then
    sudo cp -a "$GUEST_ASSETS_DIR/fsx/." "$MOUNT_POINT/fsx/"
fi
if [ -d "$GUEST_ASSETS_DIR/pjdfstest" ]; then
    sudo cp -a "$GUEST_ASSETS_DIR/pjdfstest/." "$MOUNT_POINT/pjdfstest/"
fi
sudo chown -R root:root "$MOUNT_POINT/exploit" "$MOUNT_POINT/benchmark" "$MOUNT_POINT/unit-tests" "$MOUNT_POINT/fsx" "$MOUNT_POINT/pjdfstest"
sudo chmod -R 755 "$MOUNT_POINT/exploit" "$MOUNT_POINT/benchmark" "$MOUNT_POINT/unit-tests" "$MOUNT_POINT/fsx" "$MOUNT_POINT/pjdfstest"

# Install autorun systemd unit and script
log_step "Installing headless autorun service"
if [ -f "$GUEST_ASSETS_DIR/autorun/pks-autorun.sh" ]; then
    sudo cp "$GUEST_ASSETS_DIR/autorun/pks-autorun.sh" "$MOUNT_POINT/usr/local/bin/pks-autorun.sh"
    sudo chmod 755 "$MOUNT_POINT/usr/local/bin/pks-autorun.sh"
fi
if [ -f "$GUEST_ASSETS_DIR/autorun/pks-autorun.service" ]; then
    sudo cp "$GUEST_ASSETS_DIR/autorun/pks-autorun.service" "$MOUNT_POINT/etc/systemd/system/pks-autorun.service"
    sudo mkdir -p "$MOUNT_POINT/etc/systemd/system/multi-user.target.wants"
    sudo ln -sf /etc/systemd/system/pks-autorun.service \
        "$MOUNT_POINT/etc/systemd/system/multi-user.target.wants/pks-autorun.service"
fi

if [ -f "$MOUNT_POINT/exploit/dirty-frag/exp.c" ]; then
    log_step "Compiling dirty-frag harness inside chroot"
    sudo chroot "$MOUNT_POINT" /bin/bash -c "
        cd /exploit/dirty-frag && gcc -O0 -Wall -o exp exp.c -lutil
    " 2>/dev/null || log_warn "dirty-frag compilation inside chroot skipped or failed"
fi

if [ -f "$MOUNT_POINT/exploit/fragnesia/exp.c" ]; then
    log_step "Compiling fragnesia harness inside chroot"
    sudo chroot "$MOUNT_POINT" /bin/bash -c "
        cd /exploit/fragnesia && gcc -O2 -Wall -o exp exp.c
    " 2>/dev/null || log_warn "fragnesia compilation inside chroot skipped or failed"
fi

if [ -f "$MOUNT_POINT/unit-tests/pks_sanity_test.c" ]; then
    log_step "Compiling pks_sanity_test inside chroot"
    sudo chroot "$MOUNT_POINT" /bin/bash -c "
        cd /unit-tests && gcc -O2 -Wall -o pks_sanity_test pks_sanity_test.c
    " 2>/dev/null || log_warn "pks_sanity_test compilation inside chroot skipped or failed"
fi

if [ -f "$MOUNT_POINT/fsx/fsx.c" ]; then
    log_step "Compiling fsx harness inside chroot"
    sudo chroot "$MOUNT_POINT" /bin/bash -c "
        cd /fsx && make clean && make
    " 2>/dev/null || log_warn "fsx compilation inside chroot skipped or failed"
fi

if [ -f "$MOUNT_POINT/pjdfstest/pjdfstest.c" ]; then
    log_step "Compiling pjdfstest inside chroot"
    sudo chroot "$MOUNT_POINT" /bin/bash -c "
        cd /pjdfstest && gcc -Wall -O2 pjdfstest.c -o pjdfstest
    " 2>/dev/null || log_warn "pjdfstest compilation inside chroot skipped or failed"
fi

# Clean up chroot binds before exit
sudo umount "$MOUNT_POINT/dev"
sudo umount "$MOUNT_POINT/proc"
sudo umount "$MOUNT_POINT/sys"

log_ok "Disk image provisioning complete: $DISK_IMG"