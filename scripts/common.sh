#!/usr/bin/env bash
# scripts/common.sh - Shared logging and environment helpers
set -euo pipefail

# ANSI color codes
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'

log_done() {
    echo -e "${C_GREEN}[DONE]${C_RESET} $1"
}

log_fail() {
    echo -e "${C_RED}[FAIL]${C_RESET} $1" >&2
}

log_warn() {
    echo -e "${C_YELLOW}[WARN]${C_RESET} $1"
}

log_info() {
    echo -e "${C_BLUE}[INFO]${C_RESET} $1"
}

die() {
    log_fail "$1"
    exit 1
}

require_cmds() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' is not installed."
    done
}
