#!/usr/bin/env bash
# ==============================================================================
# build/sec/run.sh - Build the security diagnostic kernel (PKS + introspection)
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/build/build_kernel.sh"

KERNEL_DIR="${DEV_KERNEL_DIR:-$HOME/src/linux-pks-thesis}"
build_kernel sec "$KERNEL_DIR"

