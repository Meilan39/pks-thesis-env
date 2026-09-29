#!/usr/bin/env bash
# build/sec/run.sh - compile the security diagnostic kernel (PKS + introspection).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"
source "$ROOT/build/build_kernel.sh"
build_kernel sec "${DEV_KERNEL_DIR:-$HOME/src/linux-pks-thesis}"
