#!/usr/bin/env bash
# preflight.sh - Verify host dependencies, detect execution substrate, and record
# environmental provenance.
# Executed before all top-level workflow targets. Fails fast on missing dependencies.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
source "$REPO_ROOT/common.sh"

RESULTS_DIR="$REPO_ROOT/results"
mkdir -p "$RESULTS_DIR"

# ==============================================================================
# 1. Host Dependency Verification
# ==============================================================================
require_cmds "${QEMU_BIN:-qemu-system-x86_64}" python3 gcc

# ==============================================================================
# 2. Execution Substrate Detection
# ==============================================================================
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
        log_done "Substrate: KVM with hardware PKS (hardware enforcement active)."
        ;;
    kvm-nopks)
        log_warn "Substrate: KVM available but host CPU lacks PKS; security tests require TCG emulation."
        ;;
    tcg)
        log_warn "Substrate: TCG emulation (no /dev/kvm). PKS enforcement is emulated; negative controls validate behavior."
        ;;
esac

# ==============================================================================
# 3. Environmental Provenance Record
# ==============================================================================
host_kernel="$(uname -sr 2>/dev/null || echo unknown)"
cpu_model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || echo unknown)"
qemu_version="$("${QEMU_BIN:-qemu-system-x86_64}" --version 2>/dev/null | head -n1 || echo unknown)"

cat > "$RESULTS_DIR/preflight.json" <<EOF
{
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "host_kernel": "$host_kernel",
  "cpu_model": "$cpu_model",
  "substrate": "$substrate",
  "qemu": "$qemu_version",
  "smp": ${SMP:-4},
  "mem_mb": ${MEM:-4096}
}
EOF

log_done "Preflight recorded ($substrate) -> results/preflight.json"

