#!/usr/bin/env bash
# ==============================================================================
# test/sanity/run.sh - PKS Page-Cache Scoping and Subsystem Sanity Test
# ==============================================================================
# Validates the in-kernel PKS page-cache protection contract across four suites:
# 1. Sanctioned write-path scoping (write, pwrite, writev, ftruncate, fallocate)
# 2. Static pool page-cache residency (PFN bounds via /proc/self/pagemap)
# 3. Fail-closed rejection matrix (mmap(PROT_WRITE), O_DIRECT, splice, sendfile,
#    copy_file_range, AIO, EXT4_IOC_MOVE_EXT -> all -EOPNOTSUPP)
# 4. Permitted-operation positive controls (buffered I/O round-trip, truncation,
#    read-only mappings, blocked writable upgrade: no false rejections)
#
# The verdict is derived purely by counting [PASS]/[FAIL] lines; [SKIP] lines
# (environment preconditions unmet) are ignored.
#
# These invariants hold ONLY when pcache_pks=on with the protected mount active.
# Under off/control, the PKS pool is inactive, so the checks are not applicable.
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/common.sh"

VARIANT="${1:-on}"
SANITY_BIN="$SCRIPT_DIR/pks_sanity_test"

# Sanity assertions apply strictly to PKS-enabled mode
if [ "$VARIANT" != "on" ]; then
    emit_status sanity "$VARIANT" PASS note=not_applicable_when_off
    exit 0
fi

# Compile sanity harness if absent
if [ ! -x "$SANITY_BIN" ] && [ -f "$SCRIPT_DIR/pks_sanity_test.c" ]; then
    gcc -O2 -Wall -o "$SANITY_BIN" "$SCRIPT_DIR/pks_sanity_test.c" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 1. Execute Sanity Test Suite
# ------------------------------------------------------------------------------
# Stream the harness output straight to stdout: systemd forwards it to the serial
# console, which the axis runner captures into test/raw-<variant>.log. No redirect
# and no scratch file -- the transcript IS the per-check record. stdbuf -oL keeps
# the [PASS]/[FAIL]/[SKIP] lines live and ordered. The binary's exit code is the
# verdict: pks_sanity_test returns nonzero iff any contract assertion failed.
rc=127
if [ -x "$SANITY_BIN" ]; then
    stdbuf -oL -eL "$SANITY_BIN"
    rc=$?
fi

# ------------------------------------------------------------------------------
# 2. Verdict Evaluation
# ------------------------------------------------------------------------------
if [ "$rc" -eq 127 ]; then
    emit_status sanity "$VARIANT" FAIL note=harness_absent
elif [ "$rc" -eq 0 ]; then
    emit_status sanity "$VARIANT" PASS
else
    emit_status sanity "$VARIANT" FAIL rc="$rc"
fi
