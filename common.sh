#!/usr/bin/env bash
# common.sh - Shared logging, the STATUS node contract, and result harvesting.
#
# Sourced by both host orchestrators and in-guest runners. It sets NO shell
# options (each script owns its own `set`), so sourcing never changes caller
# behaviour.
#
# THE NODE CONTRACT
#   Every node directory has a run.sh and (generated) result.log.
#   A leaf run.sh emits, on stdout, one line per observed result:
#       STATUS node=<name> variant=<control|off|on> verdict=<V> [k=v]...
#   where V in PASS|FAIL|NEUTRALIZED|VULNERABLE|PENDING.
#     PASS, NEUTRALIZED   -> passing
#     FAIL, VULNERABLE    -> failing
#     PENDING             -> emitted before a possibly-fatal step; the host
#                            resolves it from the boot transcript (panic path).
#   Only STATUS lines are parsed; humans read the same file. result.log is the
#   parsed/latest/rolled-up summary. Full transcripts + JSON are archived raw.

# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------
C_RESET='\033[0m'; C_RED='\033[31m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_BLUE='\033[34m'
log_info() { printf '%b[INFO]%b %s\n' "$C_BLUE"   "$C_RESET" "$1"; }
log_done() { printf '%b[DONE]%b %s\n' "$C_GREEN"  "$C_RESET" "$1"; }
log_warn() { printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
log_fail() { printf '%b[FAIL]%b %s\n' "$C_RED"    "$C_RESET" "$1" >&2; }
die()      { log_fail "$1"; exit 1; }
require_cmds() { local c; for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "Required command '$c' is not installed."; done; }

# ----------------------------------------------------------------------------
# Kernel-side signatures used to classify a panicked security run. Overridable
# from config.mk / the environment; defaults match pks-thesis-implementation-3.
# PKS_ACTIVE_REGEX : proves the PKS pool was initialised on this boot.
# PKS_PANIC_REGEX  : proves an unhandled supervisor fault / panic fired.
# ----------------------------------------------------------------------------
PKS_ACTIVE_REGEX="${PKS_ACTIVE_REGEX:-pcache_pks: initialized}"
PKS_PANIC_REGEX="${PKS_PANIC_REGEX:-Kernel panic|unable to handle .*page fault|BUG: |Oops|general protection|protection key}"

# ----------------------------------------------------------------------------
# STATUS emission / parsing
# ----------------------------------------------------------------------------
# emit_status <node> <variant> <verdict> [extra k=v]...
emit_status() {
    local node="$1" variant="$2" verdict="$3"; shift 3
    printf 'STATUS node=%s variant=%s verdict=%s' "$node" "$variant" "$verdict"
    local kv; for kv in "$@"; do printf ' %s' "$kv"; done
    printf '\n'
}

# status_field <line> <key> -> value on stdout
status_field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n1; }

# verdict_is_pass <verdict> -> exit 0 if passing
verdict_is_pass() { case "$1" in PASS|NEUTRALIZED) return 0;; *) return 1;; esac; }

# ----------------------------------------------------------------------------
# Harvesting (host side)
# ----------------------------------------------------------------------------
# harvest_node <transcript> <node> <leaf_result_log>
#   Append the (non-PENDING) STATUS line for <node> found in a boot transcript
#   to a leaf result.log. Used for the consolidated test/perf axes.
harvest_node() {
    local t="$1" node="$2" out="$3" line
    line=$(grep '^STATUS ' "$t" 2>/dev/null | grep -F "node=$node " | grep -v 'verdict=PENDING' | tail -n1 || true)
    [ -n "$line" ] && printf '%s\n' "$line" >> "$out"
}

# classify_sec <transcript> <node> <variant> <leaf_result_log>
#   Resolve one security leaf from a boot transcript. A final (non-PENDING)
#   STATUS wins; otherwise a PKS-attributable panic is a fail-closed
#   neutralization; anything else is an inconclusive FAIL. Pure observation.
classify_sec() {
    local t="$1" node="$2" variant="$3" out="$4" resolved
    resolved=$(grep '^STATUS ' "$t" 2>/dev/null | grep -F "node=$node " | grep -v 'verdict=PENDING' | tail -n1 || true)
    if [ -n "$resolved" ]; then printf '%s\n' "$resolved" >> "$out"; return; fi
    if grep -qE "$PKS_PANIC_REGEX" "$t" 2>/dev/null; then
        if grep -qE "$PKS_ACTIVE_REGEX" "$t" 2>/dev/null; then
            emit_status "$node" "$variant" NEUTRALIZED signal=fail_closed_panic marker=intact >> "$out"
        else
            emit_status "$node" "$variant" FAIL signal=panic_without_pks_active >> "$out"
        fi
    else
        emit_status "$node" "$variant" FAIL note=no_verdict_no_panic >> "$out"
    fi
}

# ----------------------------------------------------------------------------
# Roll-up (host side)
# ----------------------------------------------------------------------------
# rollup <self_result_log> <label> <child_result_log>...
#   Concatenate children's STATUS lines into self, append one rollup STATUS,
#   and return nonzero iff any child STATUS is failing.
rollup() {
    local self="$1" label="$2"; shift 2
    : > "$self"
    local child
    for child in "$@"; do [ -f "$child" ] && { grep '^STATUS ' "$child" >> "$self" 2>/dev/null || true; }; done
    local pass=0 fail=0 line verdict
    while IFS= read -r line; do
        verdict=$(status_field "$line" verdict)
        if verdict_is_pass "$verdict"; then pass=$((pass+1)); else fail=$((fail+1)); fi
    done < <(grep '^STATUS ' "$self" 2>/dev/null || true)
    # No results harvested is a failure, never a vacuous pass.
    local overall=PASS
    [ "$fail" -gt 0 ] && overall=FAIL
    [ "$((pass+fail))" -eq 0 ] && overall=FAIL
    emit_status "$label" all "$overall" "passed=$pass" "failed=$fail" >> "$self"
    log_info "[$label] rollup: $pass passing, $fail failing (verdict=$overall)"
    [ "$overall" = PASS ]
}

# mark_empty_leaves <variant> <leaf_result_log>...
#   Ensure every expected leaf produced at least one STATUS; a silent gap
#   (boot failure, crash before emit) becomes a visible FAIL rather than
#   vanishing from the rollup.
mark_empty_leaves() {
    local variant="$1"; shift
    local leaf node
    for leaf in "$@"; do
        if ! grep -q '^STATUS ' "$leaf" 2>/dev/null; then
            node="$(basename "$(dirname "$leaf")")"
            emit_status "$node" "$variant" FAIL note=no_status >> "$leaf"
        fi
    done
}

# statuses_to_csv <result_log> <csv_out>
#   Flatten STATUS lines into a wide CSV (node,variant,verdict + any extra keys).
statuses_to_csv() {
    local src="$1" out="$2"
    awk '
        /^STATUS / {
            delete f; n=0
            for (i=2;i<=NF;i++){ split($i,kv,"="); f[kv[1]]=kv[2]; if(!(kv[1] in seen)){seen[kv[1]]=1; order[++n_keys]=kv[1]} }
            rows[++nr]=$0
        }
        END {
            # header: stable core keys first
            printf "node,variant,verdict"
            for (k=1;k<=n_keys;k++){ if(order[k]!="node"&&order[k]!="variant"&&order[k]!="verdict") printf ",%s",order[k] }
            printf "\n"
            for (r=1;r<=nr;r++){
                delete f
                split(rows[r],parts," ")
                for (i=2;i<=length(parts);i++){ split(parts[i],kv,"="); f[kv[1]]=kv[2] }
                printf "%s,%s,%s", f["node"], f["variant"], f["verdict"]
                for (k=1;k<=n_keys;k++){ key=order[k]; if(key!="node"&&key!="variant"&&key!="verdict") printf ",%s",(key in f?f[key]:"") }
                printf "\n"
            }
        }' "$src" > "$out"
}
