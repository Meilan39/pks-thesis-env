#!/usr/bin/env bash
# ==============================================================================
# scripts/run_compliance.sh - Single-boot compliance & functional validation
# ==============================================================================
# Runs PKS hardware sanity, fsx filesystem exerciser, and POSIX conformance
# in a single QEMU boot under pcache_pks=on.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ENV_DIR/results}"

log_header "PKS Thesis: Consolidated Compliance Suite (Single Boot)"
log_info "Booting mitigated security kernel with pks_auto=compliance..."

# 1. Execute QEMU with compliance autorun
"$SCRIPT_DIR/run_qemu_sec.sh" on --batch compliance

# 2. Extract disk artifacts to host results
log_step "Harvesting compliance artifacts from disk image..."
"$SCRIPT_DIR/fetch_results.sh" "$RESULTS_DIR/extracted" >/dev/null 2>&1 || true

# 3. Display summary
echo ""
echo "======================================================================"
echo " Compliance & Functional Integrity Summary"
echo "======================================================================"

if [ -f "$RESULTS_DIR/compliance.log" ]; then
    grep -E "(=== \[|PASSED|FAILED|PASS|FAIL|Summary|Final Result|All tests passed)" \
        "$RESULTS_DIR/compliance.log" | grep -v "grep" || true
else
    log_warn "No compliance log found at $RESULTS_DIR/compliance.log"
fi

echo "======================================================================"
log_ok "Compliance test run complete. Detailed log: $RESULTS_DIR/compliance.log"
