#!/usr/bin/env bash
# build/build_kernel.sh - Shared kernel build routine, sourced by the build
# leaves. Configures via checked-in fragments (configs/) merged onto defconfig,
# compiles bzImage, and emits one STATUS line reflecting the real outcome.
#
#   build_kernel <variant> <kernel_tree>
#     variant     : control | sec | perf   (selects configs/<variant>.config)
#     kernel_tree : path to the external, version-agnostic kernel source
#   Output image: <kernel_tree>/build_<variant>/arch/x86/boot/bzImage

build_kernel() {
    local variant="$1" kdir="$2"
    local root; root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "$root/common.sh"

    local out="$kdir/build_${variant}"
    local jobs="${BUILD_JOBS:-$(nproc 2>/dev/null || echo 4)}"
    local rawlog="$root/build/${variant}/raw.log"
    mkdir -p "$(dirname "$rawlog")"

    require_cmds make gcc bc flex bison
    if [ ! -d "$kdir" ]; then
        emit_status "build-$variant" "$variant" FAIL note=missing_kernel_tree path="$kdir"
        return 1
    fi

    local start; start=$(date +%s)
    log_info "[build-$variant] configure + compile ($kdir) -> $rawlog"
    (
        set -e
        cd "$kdir"
        make O="$out" defconfig
        make O="$out" kvm_guest.config || true
        ./scripts/kconfig/merge_config.sh -m -O "$out" "$out/.config" \
            "$root/configs/common.config" "$root/configs/${variant}.config"
        make O="$out" olddefconfig
        make O="$out" -j"$jobs" bzImage
    ) >> "$rawlog" 2>&1 || true

    local bz="$out/arch/x86/boot/bzImage" secs=$(( $(date +%s) - start ))
    if [ -f "$bz" ]; then
        local sz; sz=$(stat -c%s "$bz" 2>/dev/null || stat -f%z "$bz" 2>/dev/null || echo 0)
        emit_status "build-$variant" "$variant" PASS bytes="$sz" secs="$secs"
        log_done "[build-$variant] bzImage ready (${secs}s)"
    else
        emit_status "build-$variant" "$variant" FAIL note=no_bzimage log="$rawlog"
        log_fail "[build-$variant] failed; see $rawlog"
    fi
}
