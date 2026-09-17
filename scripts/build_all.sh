#!/usr/bin/env bash
# ==============================================================================
# scripts/build_all.sh - Autonomous orchestrator for kernel compilation & disk image
# ==============================================================================
# Sequentially builds security, performance, and control kernels, then prepares
# the disk image. Supports detached tmux execution for unattended runs.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ENV_DIR/results}"
DISK_IMG="${DISK_IMG:-$ENV_DIR/images/disk.img}"
BUILD_LOG="$RESULTS_DIR/build.log"
mkdir -p "$RESULTS_DIR"

MODE="${1:-auto}"

# If tmux is available, user didn't request --direct, and not already inside tmux:
if [ "$MODE" != "--direct" ] && [ -z "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    if tmux has-session -t pks-build 2>/dev/null; then
        log_warn "A build session 'pks-build' is already running."
        echo "       Attach with: tmux attach -t pks-build"
        exit 0
    fi
    log_header "Launching Autonomous Background Build (tmux: pks-build)"
    tmux new-session -d -s pks-build "bash '$SCRIPT_DIR/build_all.sh' --direct"
    log_ok "Build session 'pks-build' started in background."
    log_kv "Attach Session" "tmux attach -t pks-build"
    log_kv "Log File"       "$BUILD_LOG"
    exit 0
fi

# Direct sequential execution
exec > >(tee -a "$BUILD_LOG") 2>&1

log_header "PKS Thesis: Autonomous Build Pipeline"
log_kv "Start Time" "$(date)"
log_kv "Build Log"  "$BUILD_LOG"

# 1. Security Kernel
log_step "[1/4] Compiling Security Kernel (build_sec)..."
"$SCRIPT_DIR/build_sec.sh"

# 2. Mitigated Performance Kernel
log_step "[2/4] Compiling Mitigated Performance Kernel (build_perf)..."
"$SCRIPT_DIR/build_perf.sh"

# 3. Baseline Control Kernel
log_step "[3/4] Compiling Baseline Control Kernel (build_control)..."
"$SCRIPT_DIR/build_control.sh"

# 4. Disk Image Lifecycle
log_step "[4/4] Preparing Disk Image ($DISK_IMG)..."
if [ -f "$DISK_IMG" ] && [ "${FORCE_REPROVISION:-0}" != "1" ]; then
    log_info "Existing disk image detected. Synchronizing guest assets via update_disk.sh..."
    "$SCRIPT_DIR/update_disk.sh" "$DISK_IMG"
else
    log_info "Provisioning disk image via provision_disk.sh..."
    "$SCRIPT_DIR/provision_disk.sh" "$DISK_IMG"
fi

log_header "Build Pipeline Completed Successfully"
log_kv "End Time" "$(date)"
log_ok "All kernels compiled and disk image prepared."
