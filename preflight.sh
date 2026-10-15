#!/usr/bin/env bash
# ==============================================================================
# preflight.sh - Host dependency check, substrate detection, provenance record
# ==============================================================================
# Runs before every top-level axis; fails fast on a missing dependency.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
source "$REPO_ROOT/common.sh"

RESULTS_DIR="$REPO_ROOT/results"
mkdir -p "$RESULTS_DIR"

# ------------------------------------------------------------------------------
# Resolve execution substrate (auto -> qemu | baremetal)
# ------------------------------------------------------------------------------
executor="$(resolve_executor "${EXECUTOR:-auto}")"

# ------------------------------------------------------------------------------
# Host dependencies (QEMU is only needed for the qemu adapter)
# ------------------------------------------------------------------------------
require_cmds python3 gcc
if [ "$executor" = "qemu" ]; then
    require_cmds "${QEMU_BIN:-qemu-system-x86_64}"
fi

# ------------------------------------------------------------------------------
# Detect execution substrate
# ------------------------------------------------------------------------------
if [ "$executor" = "baremetal" ]; then
    # Native: this host is the booted PKS test kernel; leaves run on real silicon.
    substrate="baremetal-pks"
    log_done "Substrate: bare metal with native PKS (leaves run on real silicon, zero virtualization overhead)."
else
    substrate="tcg"
    if [ -e /dev/kvm ] && [ -w /dev/kvm ]; then
        if grep -qw pks /proc/cpuinfo 2>/dev/null; then
            substrate="kvm-pks"
        else
            substrate="kvm-nopks"
        fi
    fi

    case "$substrate" in
        kvm-pks)
            log_done "Substrate: KVM with hardware PKS (guest uses real PKS silicon; near-native MSR cost)."
            ;;
        kvm-nopks)
            log_warn "Substrate: KVM available but host CPU lacks PKS; security tests require TCG emulation."
            ;;
        tcg)
            log_warn "Substrate: TCG emulation (no /dev/kvm). PKS enforcement is emulated; negative controls validate behavior."
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# Provenance record
# ------------------------------------------------------------------------------
host_kernel="$(uname -sr 2>/dev/null || echo unknown)"
cpu_model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || echo unknown)"
qemu_version="$("${QEMU_BIN:-qemu-system-x86_64}" --version 2>/dev/null | head -n1 || echo unknown)"

cat > "$RESULTS_DIR/preflight.json" <<EOF
{
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "host_kernel": "$host_kernel",
  "cpu_model": "$cpu_model",
  "executor": "$executor",
  "substrate": "$substrate",
  "qemu": "$qemu_version",
  "smp": ${SMP:-4},
  "mem_mb": ${MEM:-4096}
}
EOF

log_done "Preflight recorded (executor=$executor substrate=$substrate) -> results/preflight.json"
