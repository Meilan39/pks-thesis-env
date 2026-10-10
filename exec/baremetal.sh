#!/usr/bin/env bash
# ==============================================================================
# exec/baremetal.sh - Bare-metal substrate adapter (STUB)
# ==============================================================================
# Same executor contract as exec/qemu.sh:
#     exec/baremetal.sh <kernel_variant> <pks_mode> <target> [transcript_out]
#
# A real PKS-host implementation would boot/kexec the bzImage, deliver the target
# by writing /mnt/protected/.pks-run (guest/autorun.sh reads it), then capture
# serial/SSH console output to <transcript_out>. The leaves and harvest contract
# are substrate-agnostic.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common.sh"

die "exec/baremetal.sh is not yet implemented. Set EXECUTOR=qemu, or implement this adapter for your PKS host."
