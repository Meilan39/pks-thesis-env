#!/usr/bin/env bash
# build/control/run.sh - compile the pristine upstream baseline kernel.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"
source "$ROOT/build/build_kernel.sh"
build_kernel control "${CONTROL_KERNEL_DIR:-$HOME/src/linux-pks-thesis-control}"
