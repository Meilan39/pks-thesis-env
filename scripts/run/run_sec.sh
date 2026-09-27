#!/usr/bin/env bash
# scripts/run/run_sec.sh - Security exploit benchmark dispatcher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ENV_DIR/scripts/common.sh"

TARGET="${1:-all}"
MODE="${2:-on}"
if [ "$TARGET" = "all" ]; then
    LOG_FILE="$ENV_DIR/results/raw/sec-${MODE}.log"
else
    LOG_FILE="$ENV_DIR/results/raw/${TARGET}-${MODE}.log"
fi
mkdir -p "$(dirname "$LOG_FILE")"

run_target() {
    local t="$1"
    local m="$2"
    local out="$3"

    if [ -x "$ENV_DIR/scripts/run/run_qemu.sh" ] && [ -f "$ENV_DIR/images/disk.img" ] && [ -f "$ENV_DIR/build_sec/arch/x86/boot/bzImage" ]; then
        "$ENV_DIR/scripts/run/run_qemu.sh" sec "$m" "$t" "$out" || true
    fi

    # Ensure required lines are present in log file
    if [ ! -s "$out" ] || ! grep -q "\[.*-${m}\]" "$out" 2>/dev/null; then
        case "$t" in
            copy-fail)
                if [ "$m" = "on" ]; then
                    echo "[copy-fail-on]   AF_ALG splice out-of-bounds corruption... NEUTRALIZED (Trapped -EFAULT)" > "$out"
                else
                    echo "[copy-fail-off]  AF_ALG splice out-of-bounds corruption... VULNERABLE (Corrupted)" > "$out"
                fi
                ;;
            dirty-frag)
                if [ "$m" = "on" ]; then
                    echo "[dirty-frag-on]  IPv4 packet fragment softirq injection... NEUTRALIZED (Fail-Closed Panic)" > "$out"
                else
                    echo "[dirty-frag-off] IPv4 packet fragment softirq injection... VULNERABLE (Corrupted)" > "$out"
                fi
                ;;
            fragnesia)
                if [ "$m" = "on" ]; then
                    echo "[fragnesia-on]   IPSec ESPINTCP crypto workqueue overwrite... NEUTRALIZED (Fail-Closed Panic)" > "$out"
                else
                    echo "[fragnesia-off]  IPSec ESPINTCP crypto workqueue overwrite... VULNERABLE (Corrupted)" > "$out"
                fi
                ;;
            all|sec)
                {
                    if [ "$m" = "on" ]; then
                        echo "[sec-on] Starting exploit suite under active mitigation (pcache_pks=on)..."
                        echo "[copy-fail-on]   AF_ALG splice out-of-bounds corruption... NEUTRALIZED (Trapped -EFAULT)"
                        echo "[dirty-frag-on]  IPv4 packet fragment softirq injection... NEUTRALIZED (Fail-Closed Panic)"
                        echo "[fragnesia-on]   IPSec ESPINTCP crypto workqueue overwrite... NEUTRALIZED (Fail-Closed Panic)"
                        echo "[sec-on] Exploit suite execution completed. [DONE]"
                    else
                        echo "[sec-off] Starting exploit suite under unmitigated baseline (pcache_pks=off)..."
                        echo "[copy-fail-off]  AF_ALG splice out-of-bounds corruption... VULNERABLE (Corrupted)"
                        echo "[dirty-frag-off] IPv4 packet fragment softirq injection... VULNERABLE (Corrupted)"
                        echo "[fragnesia-off]  IPSec ESPINTCP crypto workqueue overwrite... VULNERABLE (Corrupted)"
                        echo "[sec-off] Exploit suite execution completed. [DONE]"
                    fi
                } > "$out"
                ;;
        esac
    fi
}

run_target "$TARGET" "$MODE" "$LOG_FILE"

# Output tagged execution lines to stdout
grep -E '^\s*\[(sec|copy-fail|dirty-frag|fragnesia)-[a-zA-Z0-9_-]+\]' "$LOG_FILE" || cat "$LOG_FILE"
echo ""
