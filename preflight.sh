#!/usr/bin/env bash
# preflight.sh - Verify host deps, detect the execution substrate, and record
# provenance. Run before every top-level verb. Hard-fails only on missing deps.
set -euo pipefail

ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ENV_DIR/common.sh"

# Top-level summaries/provenance live directly under results/ (no raw/ tree).
RAW_DIR="$ENV_DIR/results"
mkdir -p "$RAW_DIR"

# 1. Host dependencies (hard requirement).
require_cmds "$QEMU_BIN" python3 gcc

# 2. Substrate detection.
substrate="tcg"
if [ -e /dev/kvm ] && [ -w /dev/kvm ]; then
    if grep -qw pks /proc/cpuinfo 2>/dev/null; then substrate="kvm-pks"; else substrate="kvm-nopks"; fi
fi

case "$substrate" in
    kvm-pks)   log_done "Substrate: KVM with hardware PKS (enforcement authoritative)." ;;
    kvm-nopks) log_warn "Substrate: KVM but CPU lacks PKS; security enforcement runs under TCG semantics." ;;
    tcg)       log_warn "Substrate: TCG (no /dev/kvm). PKS enforcement is emulated; the negative control validates it." ;;
esac

# 3. Provenance record consumed by analyzers and cited by the thesis.
host_kernel="$(uname -sr 2>/dev/null || echo unknown)"
cpu_model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || echo unknown)"
qemu_ver="$("$QEMU_BIN" --version 2>/dev/null | head -n1 || echo unknown)"

cat > "$RAW_DIR/preflight.json" <<EOF
{
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "host_kernel": "$host_kernel",
  "cpu_model": "$cpu_model",
  "substrate": "$substrate",
  "qemu": "$qemu_ver",
  "smp": $SMP,
  "mem_mb": $MEM
}
EOF

log_done "Preflight recorded ($substrate) -> results/preflight.json"
