#!/usr/bin/env bash
# ==============================================================================
# build/control/run.sh - Build the pristine upstream baseline kernel
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/build/build_kernel.sh"

KERNEL_DIR="${CONTROL_KERNEL_DIR:-$HOME/src/linux-pks-thesis-control}"
build_kernel control "$KERNEL_DIR"

