#!/usr/bin/env bash
# exec/baremetal.sh - Bare-metal substrate adapter (STUB).
#
# Implements the same executor contract as exec/qemu.sh:
#     exec/baremetal.sh <kernel_variant> <pks_mode> <target> [transcript_out]
#
# A real implementation on a PKS-capable baremetal machine would:
#   1. Boot or kexec the prebuilt bzImage,
#   2. Deliver runtime parameters by writing /mnt/protected/.pks-run = <target>
#      (guest/autorun.sh reads that file when present, keeping the workload identical),
#   3. Connect over serial or SSH, execute the workload, and capture console output
#      to <transcript_out>.
#
# The workload leaves and harvest contract are substrate-agnostic.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

die "exec/baremetal.sh is not yet implemented. Set EXECUTOR=qemu, or implement this adapter for your PKS host."

