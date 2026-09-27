#!/usr/bin/env bash
# scripts/clean-all.sh - Clean all compiled evaluation binaries
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

for dir in tests sec perf; do
    if [ -f "$ENV_DIR/$dir/Makefile" ]; then
        make -C "$ENV_DIR/$dir" clean >/dev/null 2>&1 || true
    fi
done

echo "[clean] Cleared all compiled binaries across tests/, sec/, and perf/. [DONE]"
echo ""
