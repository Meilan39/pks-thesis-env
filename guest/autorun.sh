#!/usr/bin/env bash
# ==============================================================================
# guest/autorun.sh - In-guest workload dispatcher (systemd, once at boot)
# ==============================================================================
# Resolves the target and variant from /proc/cmdline, mounts the needed
# filesystems (9p workspace, protected ext4, debugfs), runs the matching leaves,
# and powers off. Results stream over serial as STATUS lines; nothing is written
# in-guest, for crash resilience.
# ==============================================================================
set -u

# ------------------------------------------------------------------------------
# Heartbeat & helpers
# ------------------------------------------------------------------------------
hb() {
    echo "HB autorun: $*"
}

CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"

cmd_val() {
    local key="$1"
    printf '%s\n' "$CMDLINE" | tr ' ' '\n' | sed -n "s/^${key}=//p" | tail -n1
}

hb "reached (cmdline: $CMDLINE)"

# ------------------------------------------------------------------------------
# Resolve target
# ------------------------------------------------------------------------------
# From kernel cmdline (QEMU), or overridden by /mnt/protected/.pks-run (baremetal).
TARGET="$(cmd_val pks_run)"
if [ -z "$TARGET" ]; then
    TARGET="$(cmd_val pks_auto)"
fi

if [ -f /mnt/protected/.pks-run ]; then
    TARGET="$(cat /mnt/protected/.pks-run 2>/dev/null || true)"
fi

if [ -z "$TARGET" ] || [ "$TARGET" = "shell" ]; then
    hb "no run target; exiting"
    exit 0
fi
hb "target=$TARGET"

# ------------------------------------------------------------------------------
# Mount 9p workspace
# ------------------------------------------------------------------------------
if ! mountpoint -q /pks-thesis-env 2>/dev/null; then
    mkdir -p /pks-thesis-env
    mount -t 9p -o trans=virtio,version=9p2000.L,nofail pks_env /pks-thesis-env 2>/dev/null || true
fi

WORKSPACE_DIR="/pks-thesis-env"
if [ ! -d "$WORKSPACE_DIR/test" ]; then
    WORKSPACE_DIR="/"
fi

hb "9p_mounted=$(mountpoint -q /pks-thesis-env && echo yes || echo no) ws=$WORKSPACE_DIR common.sh=$([ -f "$WORKSPACE_DIR/common.sh" ] && echo yes || echo no)"

# ------------------------------------------------------------------------------
# Detect variant
# ------------------------------------------------------------------------------
MODE="off"
if printf '%s' "$CMDLINE" | grep -q 'pcache_pks=on'; then
    MODE="on"
fi

LABEL="$MODE"
if printf '%s' "$CMDLINE" | grep -q 'pcache_control=1'; then
    LABEL="control"
fi

# ------------------------------------------------------------------------------
# Mount protected partition & debugfs
# ------------------------------------------------------------------------------
if [ -b /dev/vda2 ]; then
    mkdir -p /mnt/protected
    if [ "$MODE" = "on" ]; then
        if ! grep -q '/mnt/protected.*pks_pagecache' /proc/mounts 2>/dev/null; then
            umount -l /mnt/protected 2>/dev/null || true
            mount -o pks_pagecache /dev/vda2 /mnt/protected 2>/dev/null || true
        fi
    else
        if grep -q '/mnt/protected.*pks_pagecache' /proc/mounts 2>/dev/null; then
            umount -l /mnt/protected 2>/dev/null || true
            mount /dev/vda2 /mnt/protected 2>/dev/null || true
        elif ! mountpoint -q /mnt/protected 2>/dev/null; then
            mount /dev/vda2 /mnt/protected 2>/dev/null || true
        fi
    fi
fi

hb "protected_mounted=$(mountpoint -q /mnt/protected && echo yes || echo no) mode=$MODE label=$LABEL pks_opt=$(grep -q '/mnt/protected.*pks_pagecache' /proc/mounts 2>/dev/null && echo yes || echo no)"

# debugfs for the security introspection kernel
if ! mountpoint -q /sys/kernel/debug 2>/dev/null; then
    mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# Dispatch workload & shut down
# ------------------------------------------------------------------------------
run_axis() {
    local axis_dir="$1"
    local found=0
    for script in "$WORKSPACE_DIR/$axis_dir"/*/run.sh; do
        if [ -x "$script" ]; then
            found=1
            "$script" "$LABEL"
        fi
    done
    if [ "$found" -eq 0 ]; then
        hb "no executable run.sh under $WORKSPACE_DIR/$axis_dir"
    fi
}

hb "dispatch target=$TARGET"
case "$TARGET" in
    test|sec|perf)
        run_axis "$TARGET"
        ;;
    */*)
        if [ -x "$WORKSPACE_DIR/$TARGET/run.sh" ]; then
            "$WORKSPACE_DIR/$TARGET/run.sh" "$LABEL"
        else
            hb "missing $WORKSPACE_DIR/$TARGET/run.sh"
        fi
        ;;
    *)
        for axis in test sec perf; do
            if [ -x "$WORKSPACE_DIR/$axis/$TARGET/run.sh" ]; then
                "$WORKSPACE_DIR/$axis/$TARGET/run.sh" "$LABEL"
                break
            fi
        done
        ;;
esac

hb "done; powering off"
sync
sleep 0.5
poweroff -f

