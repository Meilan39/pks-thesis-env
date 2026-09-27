#!/usr/bin/env bash
# scripts/compile-all.sh - Compile all in-guest evaluation binaries
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_LOG="${RAW_LOG:-$ENV_DIR/results/raw/compile.log}"
mkdir -p "$(dirname "$RAW_LOG")"

echo "[compile] Compiling evaluation binaries across tests, sec, perf..."

for dir in tests sec perf; do
    if [ -f "$ENV_DIR/$dir/Makefile" ]; then
        make -C "$ENV_DIR/$dir" all >> "$RAW_LOG" 2>&1 || true
    fi
done

echo "[compile] Compiled all evaluation binaries across tests, sec, perf... [DONE]"
echo ""
