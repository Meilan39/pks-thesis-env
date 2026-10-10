#!/usr/bin/env bash
# ==============================================================================
# build/build_kernel.sh - Shared kernel build routine (sourced by build leaves)
# ==============================================================================
# Merges configs/ fragments onto defconfig, compiles bzImage, and emits one
# STATUS line with the real outcome.
#
#   build_kernel <variant> <kernel_tree>
#     variant     : control | sec | perf  (selects configs/<variant>.config)
#     kernel_tree : kernel source directory
#   output: <kernel_tree>/build_<variant>/arch/x86/boot/bzImage
# ==============================================================================

build_kernel() {
    local variant="$1"
    local kernel_dir="$2"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local repo_root
    repo_root="$(cd "$script_dir/.." && pwd)"
    source "$repo_root/common.sh"

    local out_dir="$kernel_dir/build_${variant}"
    local jobs="${BUILD_JOBS:-$(nproc 2>/dev/null || echo 4)}"
    local raw_log="$repo_root/build/${variant}/raw.log"
    mkdir -p "$(dirname "$raw_log")"

    # --------------------------------------------------------------------------
    # Validate inputs & dependencies
    # --------------------------------------------------------------------------
    require_cmds make gcc bc flex bison

    if [ ! -d "$kernel_dir" ]; then
        emit_status "build-$variant" "$variant" FAIL note=missing_kernel_tree path="$kernel_dir"
        return 1
    fi

    local start_time
    start_time=$(date +%s)
    log_info "[build-$variant] configure + compile ($kernel_dir) -> $raw_log"

    # --------------------------------------------------------------------------
    # Configure & compile
    # --------------------------------------------------------------------------
    (
        set -e
        cd "$kernel_dir"

        # Base defconfig + kvm guest config
        make O="$out_dir" defconfig
        make O="$out_dir" kvm_guest.config || true

        # Merge common + variant fragments
        ./scripts/kconfig/merge_config.sh -m -O "$out_dir" "$out_dir/.config" \
            "$repo_root/configs/common.config" \
            "$repo_root/configs/${variant}.config"

        make O="$out_dir" olddefconfig

        # Non-control builds must keep the PKS config (tree actually carries the patches)
        if [ "$variant" != "control" ]; then
            if ! grep -q '^CONFIG_PCACHE_PKS=y' "$out_dir/.config"; then
                echo "error: CONFIG_PCACHE_PKS=y was dropped by kconfig. Kernel tree lacks PKS patches." >&2
                exit 1
            fi
            if ! grep -q '^CONFIG_INSTRUCTION_DECODER=y' "$out_dir/.config"; then
                echo "error: CONFIG_INSTRUCTION_DECODER=y was dropped by kconfig." >&2
                exit 1
            fi
        fi

        make O="$out_dir" -j"$jobs" bzImage
    ) >> "$raw_log" 2>&1 || true

    # --------------------------------------------------------------------------
    # Validate artifact & emit status
    # --------------------------------------------------------------------------
    local bz_image="$out_dir/arch/x86/boot/bzImage"
    local elapsed_secs=$(( $(date +%s) - start_time ))

    if [ -f "$bz_image" ]; then
        local image_bytes
        image_bytes=$(stat -c%s "$bz_image" 2>/dev/null || stat -f%z "$bz_image" 2>/dev/null || echo 0)
        emit_status "build-$variant" "$variant" PASS bytes="$image_bytes" secs="$elapsed_secs"
        log_done "[build-$variant] bzImage ready (${elapsed_secs}s)"
    else
        emit_status "build-$variant" "$variant" FAIL note=no_bzimage log="$raw_log"
        log_fail "[build-$variant] failed; see $raw_log"
    fi
}
