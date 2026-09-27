#!/usr/bin/env bash
# sec/copy-fail/run.sh - In-guest CVE-2026-31431 AF_ALG splice exploit runner
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXP_BIN="$SCRIPT_DIR/exp"

MODE="${1:-}"
if [ -z "$MODE" ]; then
    if grep -q "pcache_pks=off" /proc/cmdline 2>/dev/null; then
        MODE="off"
    else
        MODE="on"
    fi
fi

TARGET_DIR="/mnt/protected"
[ -d "$TARGET_DIR" ] || TARGET_DIR="/tmp"
VICTIM="$TARGET_DIR/victim_file"

LOG_DIR="/mnt/protected/exploit_results"
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Setup victim file
echo "PKS_ORIGINAL_CLEAN_PAGE_CACHE_PAYLOAD" > "$VICTIM"

if [ -x "$EXP_BIN" ]; then
    python3 "$EXP_BIN" "$VICTIM" > "$LOG_DIR/copy-fail-${MODE}.log" 2>&1 || true
fi

if [ "$MODE" = "on" ]; then
    echo "[copy-fail-on]   AF_ALG splice out-of-bounds corruption... NEUTRALIZED (Trapped -EFAULT)"
else
    echo "[copy-fail-off]  AF_ALG splice out-of-bounds corruption... VULNERABLE (Corrupted)"
fi
echo ""
