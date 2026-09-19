#!/usr/bin/env bash
# ==============================================================================
# scripts/update_disk.sh - Synchronize updated guest assets into disk image
# ==============================================================================
# Usage: ./update_disk.sh [disk.img]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISK_IMG="${1:-${DISK_IMG:-$ENV_DIR/images/disk.img}}"
GUEST_ASSETS_DIR="${GUEST_ASSETS_DIR:-$ENV_DIR/guest-assets}"

[ -f "$DISK_IMG" ] || die "Disk image not found: $DISK_IMG"
[ -d "$GUEST_ASSETS_DIR" ] || die "Guest assets directory not found: $GUEST_ASSETS_DIR"
require_cmds losetup mount umount chroot sudo

log_header "Updating Guest Assets in Disk Image"
log_kv "Disk Image"  "$DISK_IMG"
log_kv "Assets Dir"  "$GUEST_ASSETS_DIR"

log_step "Attaching loop device with partition scanning"
LOOP=$(sudo losetup --find --show --partscan "$DISK_IMG")
sudo partprobe "$LOOP" 2>/dev/null || sudo partx -u "$LOOP" 2>/dev/null || true
sleep 1
ROOT_PART="${LOOP}p1"

if [ ! -b "$ROOT_PART" ]; then
    sudo losetup -d "$LOOP"
    die "Partition $ROOT_PART not found. Ensure the disk image is partitioned."
fi

MOUNT_POINT="$(mktemp -d)"

cleanup() {
    log_step "Detaching mounts and loop devices"
    sudo umount "$MOUNT_POINT" 2>/dev/null || true
    sudo losetup -d "$LOOP" 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

sudo mount "$ROOT_PART" "$MOUNT_POINT"

if [ -d "$GUEST_ASSETS_DIR/exploit" ]; then
    log_step "Synchronizing /exploit into guest rootfs"
    sudo rm -rf "$MOUNT_POINT/exploit"
    sudo mkdir -p "$MOUNT_POINT/exploit"
    sudo cp -a "$GUEST_ASSETS_DIR/exploit/." "$MOUNT_POINT/exploit/"
    sudo chown -R root:root "$MOUNT_POINT/exploit"
    sudo chmod -R 755 "$MOUNT_POINT/exploit"
    if [ -f "$MOUNT_POINT/exploit/run_tests.sh" ]; then
        sudo chmod +x "$MOUNT_POINT/exploit/run_tests.sh"
    fi
    if [ -f "$MOUNT_POINT/exploit/dirty-frag/exp.c" ]; then
        log_step "Recompiling dirty-frag harness inside chroot"
        sudo chroot "$MOUNT_POINT" /bin/bash -c "
            cd /exploit/dirty-frag && gcc -O0 -Wall -o exp exp.c -lutil
        " 2>/dev/null || log_warn "dirty-frag compilation inside chroot skipped"
    fi
    if [ -f "$MOUNT_POINT/exploit/fragnesia/exp.c" ]; then
        log_step "Recompiling fragnesia harness inside chroot"
        sudo chroot "$MOUNT_POINT" /bin/bash -c "
            cd /exploit/fragnesia && gcc -O2 -Wall -o exp exp.c
        " 2>/dev/null || log_warn "fragnesia compilation inside chroot skipped"
    fi
fi

if [ -d "$GUEST_ASSETS_DIR/benchmark" ]; then
    log_step "Synchronizing /benchmark into guest rootfs"
    sudo rm -rf "$MOUNT_POINT/benchmark"
    sudo mkdir -p "$MOUNT_POINT/benchmark"
    sudo cp -a "$GUEST_ASSETS_DIR/benchmark/." "$MOUNT_POINT/benchmark/"
    sudo chown -R root:root "$MOUNT_POINT/benchmark"
    sudo chmod -R 755 "$MOUNT_POINT/benchmark"
    find "$MOUNT_POINT/benchmark" -type f -name "*.sh" -exec sudo chmod +x {} +
    if ! sudo chroot "$MOUNT_POINT" which sqlite3 >/dev/null 2>&1; then
        log_step "Installing sqlite3 inside guest chroot"
        sudo chroot "$MOUNT_POINT" apt-get update >/dev/null 2>&1 || true
        sudo chroot "$MOUNT_POINT" apt-get install -y --no-install-recommends sqlite3 >/dev/null 2>&1 || log_warn "Could not install sqlite3 inside chroot"
    fi
fi

if [ -d "$GUEST_ASSETS_DIR/unit-tests" ]; then
    log_step "Synchronizing /unit-tests into guest rootfs"
    sudo rm -rf "$MOUNT_POINT/unit-tests"
    sudo mkdir -p "$MOUNT_POINT/unit-tests"
    sudo cp -a "$GUEST_ASSETS_DIR/unit-tests/." "$MOUNT_POINT/unit-tests/"
    sudo chown -R root:root "$MOUNT_POINT/unit-tests"
    sudo chmod -R 755 "$MOUNT_POINT/unit-tests"
    find "$MOUNT_POINT/unit-tests" -type f -name "*.sh" -exec sudo chmod +x {} +
    if [ -f "$MOUNT_POINT/unit-tests/pks_sanity_test.c" ]; then
        log_step "Compiling pks_sanity_test inside chroot"
        sudo chroot "$MOUNT_POINT" /bin/bash -c "
            cd /unit-tests && gcc -O2 -Wall -o pks_sanity_test pks_sanity_test.c
        " 2>/dev/null || log_warn "pks_sanity_test compilation inside chroot skipped"
    fi
fi

if [ -d "$GUEST_ASSETS_DIR/fsx" ]; then
    log_step "Synchronizing /fsx into guest rootfs"
    sudo rm -rf "$MOUNT_POINT/fsx"
    sudo mkdir -p "$MOUNT_POINT/fsx"
    sudo cp -a "$GUEST_ASSETS_DIR/fsx/." "$MOUNT_POINT/fsx/"
    sudo chown -R root:root "$MOUNT_POINT/fsx"
    sudo chmod -R 755 "$MOUNT_POINT/fsx"
    if [ -f "$MOUNT_POINT/fsx/run_fsx.sh" ]; then
        sudo chmod +x "$MOUNT_POINT/fsx/run_fsx.sh"
    fi
    if [ -f "$MOUNT_POINT/fsx/fsx.c" ]; then
        log_step "Recompiling fsx harness inside chroot"
        sudo chroot "$MOUNT_POINT" /bin/bash -c "
            cd /fsx && make clean && make
        " 2>/dev/null || log_warn "fsx compilation inside chroot skipped"
    fi
fi

if [ -d "$GUEST_ASSETS_DIR/pjdfstest" ]; then
    log_step "Synchronizing /pjdfstest into guest rootfs"
    sudo rm -rf "$MOUNT_POINT/pjdfstest"
    sudo mkdir -p "$MOUNT_POINT/pjdfstest"
    sudo cp -a "$GUEST_ASSETS_DIR/pjdfstest/." "$MOUNT_POINT/pjdfstest/"
    sudo chown -R root:root "$MOUNT_POINT/pjdfstest"
    sudo chmod -R 755 "$MOUNT_POINT/pjdfstest"
fi

# Synchronize headless autorun components
if [ -d "$GUEST_ASSETS_DIR/autorun" ]; then
    log_step "Updating headless autorun service"
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
fi

# Ensure /mnt/protected mount directory exists
sudo mkdir -p "$MOUNT_POINT/mnt/protected"

log_ok "Disk image updated successfully"