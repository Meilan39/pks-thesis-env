#!/usr/bin/env bash
# common.sh - Shared logging, STATUS node protocol, and result harvesting.
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
# 2. Kernel Panic & Security Signatures
# ==============================================================================
# Signatures used to classify fail-closed security events from kernel transcripts.
PKS_ACTIVE_REGEX="${PKS_ACTIVE_REGEX:-pcache_pks: initialized}"
PKS_PANIC_REGEX="${PKS_PANIC_REGEX:-Kernel panic|unable to handle .*page fault|BUG: |Oops|general protection|protection key}"

# ==============================================================================
# 3. STATUS Protocol Formatting & Parsing
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
# 4. Host Harvesting & Security Classification
# ==============================================================================
harvest_node() {
    local transcript_file="$1"
    local node_name="$2"
    local output_result_log="$3"

    local matching_line
    matching_line=$(_status_lines "$transcript_file" | grep -F "node=$node_name " | grep -v 'verdict=PENDING' | tail -n1 || true)
    if [ -n "$matching_line" ]; then
        printf '%s\n' "$matching_line" >> "$output_result_log"
    fi
}

classify_sec() {
    local transcript_file="$1"
    local node_name="$2"
    local variant="$3"
    local output_result_log="$4"

    local resolved_line
    resolved_line=$(_status_lines "$transcript_file" | grep -F "node=$node_name " | grep -v 'verdict=PENDING' | tail -n1 || true)
    if [ -n "$resolved_line" ]; then
        printf '%s\n' "$resolved_line" >> "$output_result_log"
        return
    fi

    # Evaluate fail-closed panic attribution
    if grep -qE "$PKS_PANIC_REGEX" "$transcript_file" 2>/dev/null; then
        if grep -qE "$PKS_ACTIVE_REGEX" "$transcript_file" 2>/dev/null; then
            emit_status "$node_name" "$variant" NEUTRALIZED marker=intact note=fail_closed_panic >> "$output_result_log"
        else
            emit_status "$node_name" "$variant" FAIL note=panic_without_pks_active >> "$output_result_log"
        fi
    else
        emit_status "$node_name" "$variant" FAIL note=no_verdict_no_panic >> "$output_result_log"
    fi
}

# ==============================================================================
# 5. Status Rollup & CSV Export
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

mark_empty_leaves() {
    local variant="$1"
    shift

    local leaf_log
    local node_name
    for leaf_log in "$@"; do
        if ! _status_lines "$leaf_log" | grep -q .; then
            node_name="$(basename "$(dirname "$leaf_log")")"
            emit_status "$node_name" "$variant" FAIL note=no_status >> "$leaf_log"
        fi
    done
}

statuses_to_csv() {
    local source_log="$1"
    local output_csv="$2"

    awk '
        /^STATUS / {
            delete fields
            field_count = 0
            for (i = 2; i <= NF; i++) {
                split($i, key_value, "=")
                fields[key_value[1]] = key_value[2]
                if (!(key_value[1] in seen_keys)) {
                    seen_keys[key_value[1]] = 1
                    ordered_keys[++num_ordered_keys] = key_value[1]
                }
            }
            raw_rows[++num_rows] = $0
        }
        END {
            # Core primary headers
            printf "node,variant,verdict"
            for (k = 1; k <= num_ordered_keys; k++) {
                key = ordered_keys[k]
                if (key != "node" && key != "variant" && key != "verdict") {
                    printf ",%s", key
                }
            }
            printf "\n"

            # Row records
            for (r = 1; r <= num_rows; r++) {
                delete fields
                split(raw_rows[r], parts, " ")
                for (i = 2; i <= length(parts); i++) {
                    split(parts[i], key_value, "=")
                    fields[key_value[1]] = key_value[2]
                }
                printf "%s,%s,%s", fields["node"], fields["variant"], fields["verdict"]
                for (k = 1; k <= num_ordered_keys; k++) {
                    key = ordered_keys[k]
                    if (key != "node" && key != "variant" && key != "verdict") {
                        printf ",%s", (key in fields ? fields[key] : "")
                    }
                }
                printf "\n"
            }
        }' "$source_log" > "$output_csv"
}

