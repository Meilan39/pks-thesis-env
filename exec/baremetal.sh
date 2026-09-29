#!/usr/bin/env bash
# exec/baremetal.sh - Bare-metal substrate adapter (STUB).
#
# Implements the same contract as exec/qemu.sh:
#     exec/baremetal.sh <kernel_variant> <pks_mode> <target> [transcript_out]
#
# A real implementation on a PKS-capable server would, for the given kernel
# variant and mode:
#   1. boot/kexec the prebuilt bzImage (or assume the target host is already up),
#   2. deliver the run parameters by writing /mnt/protected/.pks-run = <target>
#      (guest/autorun.sh reads that file when present, so NO kernel-cmdline
#      injection is needed and the in-guest workload is byte-identical to QEMU),
#   3. reach the box over serial/ssh, run the workload, and stream the console
#      to <transcript_out> exactly as exec/qemu.sh does.
#
# Because the workload tree and the STATUS/harvest contract are substrate
# agnostic, adding this adapter requires zero changes to build/ test/ sec/ perf/.
set -euo pipefail
ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ENV_DIR/common.sh"
die "exec/baremetal.sh is not yet implemented. Set EXECUTOR=qemu, or implement this adapter for your PKS host."
