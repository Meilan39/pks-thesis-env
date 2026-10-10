#!/usr/bin/env bash
# common.sh - Shared logging, console reporting, STATUS node protocol, and rollup.
#
# Sourced by both host orchestrators and in-guest runners.
# Does NOT set shell options (each script owns its own strictness settings).
#
# THE NODE CONTRACT:
#   Every node directory contains a run.sh and generates a result.log.
#   A leaf run.sh emits on stdout one line per observed result:
#       STATUS node=<name> variant=<control|off|on> verdict=<V> [k=v]...
#   where V is in {PASS, FAIL, NEUTRALIZED, VULNERABLE, PENDING}.
#     - PASS, NEUTRALIZED : Successful passing state
#     - FAIL, VULNERABLE  : Failure or unmitigated state
#     - PENDING           : Pre-exploit marker resolved from panic transcripts
#
# Only lines beginning with 'STATUS ' are parsed into machine-readable summaries.
#
# All terminal styling is owned here: scripts call the log_* and report_*
# helpers and never emit ANSI color codes themselves.

# ==============================================================================
# 1. Terminal Color & Logging Utilities
# ==============================================================================
if [ -t 1 ]; then
    C_RESET='\033[0m'
    C_RED='\033[31m'
    C_GREEN='\033[32m'
    C_YELLOW='\033[33m'
    C_BLUE='\033[34m'
else
    C_RESET=''
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_BLUE=''
fi

log_info() {
    printf '%b[INFO]%b %s\n' "$C_BLUE" "$C_RESET" "$1"
}

log_done() {
    printf '%b[DONE]%b %s\n' "$C_GREEN" "$C_RESET" "$1"
}

log_warn() {
    printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$1"
}

log_fail() {
    printf '%b[FAIL]%b %s\n' "$C_RED" "$C_RESET" "$1" >&2
}

die() {
    log_fail "$1"
    exit 1
}

require_cmds() {
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            die "Required command '$cmd' is not installed."
        fi
    done
}

# ==============================================================================
# 2. Axis Console Report Formatting
# ==============================================================================
# The three evaluation axes (test, sec, perf) share one console report layout:
# an 88-column banner, a live per-leaf stream, and a summary footer. These
# helpers own every width and color decision so that axis scripts stay free of
# ANSI codes and render identically.
REPORT_WIDTH=88

# Draws an 88-column rule out of a single repeated character.
_report_rule_char() {
    printf '%*s\n' "$REPORT_WIDTH" '' | tr ' ' "$1"
}

report_rule()  { _report_rule_char '='; }  # heavy banner rule
report_hrule() { _report_rule_char '-'; }  # light section rule

# Maps a verdict to its terminal color (passing is green, everything else red).
_verdict_color() {
    case "$1" in
        PASS|NEUTRALIZED) printf '%s' "$C_GREEN" ;;
        *)                printf '%s' "$C_RED" ;;
    esac
}

# report_banner <title> <subtitle>
report_banner() {
    report_rule
    printf ' %s\n' "$1"
    printf ' %s\n' "$2"
    report_rule
}

# report_leaf <tag> <mode-label> <verdict> <detail>
# One live line per leaf, e.g.:  [fsx-off]  pcache_pks=off  ... PASS (ops=10000)
report_leaf() {
    local color
    color="$(_verdict_color "$3")"
    printf ' %-20s %-15s ... %b%-4s%b (%s)\n' \
        "$1" "$2" "$color" "$3" "$C_RESET" "$4"
}

# report_check <description> <verdict>
# One indented per-check diagnostic line beneath a leaf's live line, e.g.:
#        mmap(PROT_WRITE) rejected                             PASS
# Used by axis runners that parse a leaf's per-check output out of the transcript.
# PASS is green, FAIL red, anything else (SKIP/INFO) yellow.
report_check() {
    local color
    case "$2" in
        PASS) color="$C_GREEN" ;;
        FAIL) color="$C_RED" ;;
        *)    color="$C_YELLOW" ;;
    esac
    printf '      %-56s %b%s%b\n' "$1" "$color" "$2" "$C_RESET"
}

# report_compare_head <left-title> <off-title> <on-title>
# Opens the off-vs-on summary table (rule, header row, rule).
report_compare_head() {
    report_hrule
    printf ' %-15s %-38s %-30s\n' "$1" "$2" "$3"
    report_hrule
}

# report_compare_row <name> <verdict-off> <detail-off> <verdict-on> <detail-on>
report_compare_row() {
    local color_off color_on
    color_off="$(_verdict_color "$2")"
    color_on="$(_verdict_color "$4")"
    printf ' %-15s %b%-4s%b %-33s %b%-4s%b %-25s\n' \
        "$1" "$color_off" "$2" "$C_RESET" "($3)" \
        "$color_on" "$4" "$C_RESET" "($5)"
}

# report_overall <verdict> <summary-text>
report_overall() {
    local color
    color="$(_verdict_color "$1")"
    printf ' OVERALL: %b%s%b (%s)\n' "$color" "$1" "$C_RESET" "$2"
}

# ==============================================================================
# 3. Kernel Panic & Security Signatures
# ==============================================================================
# Signatures used to classify fail-closed security events from kernel transcripts.
PKS_ACTIVE_REGEX="${PKS_ACTIVE_REGEX:-pcache_pks: initialized}"
PKS_PANIC_REGEX="${PKS_PANIC_REGEX:-Kernel panic|unable to handle .*page fault|BUG: |Oops|general protection|protection key}"
PKS_SUPPRESS_REGEX="${PKS_SUPPRESS_REGEX:-pcache_pks: (unauthorized write trapped|softirq store suppressed)}"

# ==============================================================================
# 4. STATUS Protocol Formatting & Parsing
# ==============================================================================
emit_status() {
    local node="$1"
    local variant="$2"
    local verdict="$3"
    shift 3

    printf 'STATUS node=%s variant=%s verdict=%s' "$node" "$variant" "$verdict"
    local kv_pair
    for kv_pair in "$@"; do
        printf ' %s' "$kv_pair"
    done
    printf '\n'
}

status_field() {
    local line="$1"
    local field_key="$2"
    printf '%s\n' "$line" | tr ' ' '\n' | sed -n "s/^${field_key}=//p" | head -n1
}

# Returns the trailing "k=v k=v ..." detail of a STATUS line (empty if none).
status_detail_tail() {
    printf '%s\n' "$1" | sed -E 's/^STATUS node=[^ ]+ variant=[^ ]+ verdict=[^ ]+ ?//'
}

verdict_is_pass() {
    local verdict="$1"
    local variant="${2:-}"

    case "$verdict" in
        PASS|NEUTRALIZED)
            return 0
            ;;
        VULNERABLE)
            if [ "$variant" = "off" ]; then
                return 0
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# Extracts STATUS lines from plain logs or serial transcripts containing terminal codes/journal prefixes.
_status_lines() {
    local file_path="$1"
    grep -aoE 'STATUS node=.*' "$file_path" 2>/dev/null
}

# ==============================================================================
# 5. Status Rollup
# ==============================================================================
rollup() {
    local destination_log="$1"
    local rollup_label="$2"
    shift 2

    : > "$destination_log"

    local child_log
    for child_log in "$@"; do
        if [ -f "$child_log" ]; then
            _status_lines "$child_log" >> "$destination_log" || true
        fi
    done

    local pass_count=0
    local fail_count=0
    local current_line
    local verdict
    local variant

    while IFS= read -r current_line; do
        verdict=$(status_field "$current_line" verdict)
        variant=$(status_field "$current_line" variant)
        if verdict_is_pass "$verdict" "$variant"; then
            pass_count=$((pass_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done < <(_status_lines "$destination_log" || true)

    local overall_verdict="PASS"
    if [ "$fail_count" -gt 0 ] || [ "$((pass_count + fail_count))" -eq 0 ]; then
        overall_verdict="FAIL"
    fi

    emit_status "$rollup_label" all "$overall_verdict" "passed=$pass_count" "failed=$fail_count" >> "$destination_log"
    log_info "[$rollup_label] rollup: $pass_count passing, $fail_count failing (verdict=$overall_verdict)"

    [ "$overall_verdict" = "PASS" ]
}
