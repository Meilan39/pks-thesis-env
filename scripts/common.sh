#!/usr/bin/env bash
# ==============================================================================
# scripts/common.sh - Shared logging and environment utilities
# ==============================================================================

# Enable color output if connected to a terminal and NO_COLOR is unset
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    COLOR_RESET="\033[0m"
    COLOR_BOLD="\033[1m"
    COLOR_DIM="\033[2m"
    COLOR_BLUE="\033[1;34m"
    COLOR_GREEN="\033[1;32m"
    COLOR_YELLOW="\033[1;33m"
    COLOR_RED="\033[1;31m"
    COLOR_CYAN="\033[1;36m"
else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_DIM=""
    COLOR_BLUE=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RED=""
    COLOR_CYAN=""
fi

log_info() {
    printf "${COLOR_BLUE}[INFO]${COLOR_RESET} %s\n" "$*"
}

log_ok() {
    printf "${COLOR_GREEN}[OK]${COLOR_RESET}   %s\n" "$*"
}

log_warn() {
    printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %s\n" "$*" >&2
}

log_error() {
    printf "${COLOR_RED}[ERR]${COLOR_RESET}  %s\n" "$*" >&2
}

log_step() {
    printf "${COLOR_CYAN}==>${COLOR_RESET} ${COLOR_BOLD}%s${COLOR_RESET}\n" "$*"
}

log_header() {
    local title="$1"
    local width=64
    printf "\n${COLOR_BOLD}%s${COLOR_RESET}\n" "$(printf '=%.0s' $(seq 1 $width))"
    printf "${COLOR_BOLD}  %s${COLOR_RESET}\n" "$title"
    printf "${COLOR_BOLD}%s${COLOR_RESET}\n" "$(printf '=%.0s' $(seq 1 $width))"
}

log_kv() {
    local key="$1"
    local val="$2"
    printf "  ${COLOR_DIM}%-16s${COLOR_RESET} %s\n" "$key:" "$val"
}

die() {
    log_error "$*"
    exit 1
}

# Verify that required CLI tools exist on the host
require_cmds() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        die "Missing required command(s): ${missing[*]}"
    fi
}
