#!/usr/bin/env bash
# sec/run.sh - HOST aggregator for the security axis. Each exploit runs in its
# OWN VM boot per mode (off, on) because the intended `on` outcome is a
# fail-closed kernel panic that destroys the VM - one panic must not take the
# other vectors with it. classify_sec() resolves each leaf from the serial
# transcript: a final STATUS wins; otherwise a PKS-attributable panic is a
# neutralization. Nothing is fabricated.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/.." && pwd)"
source "$ROOT/common.sh"
EXEC="$ROOT/exec/${EXECUTOR:-qemu}.sh"
LEAVES=(copy-fail dirty-frag fragnesia)

# Start clean: truncate each leaf's result.log and drop any stale raw/ from a
# previous run so nothing lingers that this run will not overwrite.
for l in "${LEAVES[@]}"; do : > "$DIR/$l/result.log"; rm -rf "$DIR/$l/raw"; done

# One boot per (leaf, mode); the transcript is leaf-local (panic isolation).
for l in "${LEAVES[@]}"; do
    for mode in off on; do
        T="$DIR/$l/raw-${mode}.log"
        "$EXEC" sec "$mode" "sec/$l" "$T"
        classify_sec "$T" "$l" "$mode" "$DIR/$l/result.log"
    done
done

for l in "${LEAVES[@]}"; do mark_empty_leaves all "$DIR/$l/result.log"; done
rollup "$DIR/result.log" sec "$DIR"/*/result.log
rc=$?
statuses_to_csv "$DIR/result.log" "$ROOT/results/data/sec_summary.csv"
exit $rc
