#!/usr/bin/env bash
# scripts/disk/disk_compile.sh - Trigger compilation of evaluation binaries
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

"$ENV_DIR/scripts/compile-all.sh"
