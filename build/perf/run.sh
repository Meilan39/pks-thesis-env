#!/usr/bin/env bash
# ==============================================================================
# build/perf/run.sh - Build the mitigated performance kernel (PKS, no debug)
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/build/build_kernel.sh"

KERNEL_DIR="${DEV_KERNEL_DIR:-$HOME/src/linux-pks-thesis}"
build_kernel perf "$KERNEL_DIR"

