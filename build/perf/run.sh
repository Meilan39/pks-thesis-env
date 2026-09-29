#!/usr/bin/env bash
# build/perf/run.sh - compile the mitigated performance kernel (PKS, no debug).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"
source "$ROOT/build/build_kernel.sh"
build_kernel perf "${DEV_KERNEL_DIR:-$HOME/src/linux-pks-thesis}"
