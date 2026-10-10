#!/usr/bin/env bash
# ==============================================================================
# test/sanity/run.sh - PKS page-cache scoping & residency contract verifier
# ==============================================================================
# Runs the four-suite contract harness (write-scope accounting, static-pool
# residency, fail-closed matrix, positive controls). The invariants hold only
# under pcache_pks=on; off/control leave the pool dormant, so the binary is not
# run and the leaf reports not-applicable.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/common.sh"

VARIANT="${1:-on}"
SANITY_BIN="$SCRIPT_DIR/pks_sanity_test"

# Not applicable when the pool is inactive
if [ "$VARIANT" != "on" ]; then
    emit_status sanity "$VARIANT" PASS note=not_applicable_when_off
    exit 0
fi

# Compile if absent
if [ ! -x "$SANITY_BIN" ] && [ -f "$SCRIPT_DIR/pks_sanity_test.c" ]; then
    gcc -O2 -Wall -o "$SANITY_BIN" "$SCRIPT_DIR/pks_sanity_test.c" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# Execute suite
# ------------------------------------------------------------------------------
# Stream [PASS]/[FAIL]/[SKIP] straight to serial (captured by the axis runner);
# no redirect, no scratch file. stdbuf -oL keeps the lines live and ordered. The
# binary exits nonzero iff any contract assertion failed, so rc is the verdict.
rc=127
if [ -x "$SANITY_BIN" ]; then
    stdbuf -oL -eL "$SANITY_BIN"
    rc=$?
fi

# ------------------------------------------------------------------------------
# Resolve verdict
# ------------------------------------------------------------------------------
if [ "$rc" -eq 127 ]; then
    emit_status sanity "$VARIANT" FAIL note=harness_absent
elif [ "$rc" -eq 0 ]; then
    emit_status sanity "$VARIANT" PASS
else
    emit_status sanity "$VARIANT" FAIL rc="$rc"
fi
