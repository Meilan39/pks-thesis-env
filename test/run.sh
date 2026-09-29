#!/usr/bin/env bash
# test/run.sh - HOST aggregator for the compliance axis. Boots the diagnostic
# (sec) kernel once per mode (off, on), runs all four compliance leaves in that
# single boot, harvests each leaf's STATUS from the serial transcript, and rolls
# up. No panics expected here, so a consolidated boot is safe.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/.." && pwd)"
source "$ROOT/common.sh"
EXEC="$ROOT/exec/${EXECUTOR:-qemu}.sh"
LEAVES=(pks-unit sanity fsx pjd)

for l in "${LEAVES[@]}"; do : > "$DIR/$l/result.log"; done

# One consolidated boot per mode; its transcript is axis-level (all leaves share it).
for mode in off on; do
    T="$DIR/raw-${mode}.log"
    "$EXEC" sec "$mode" test "$T"
    for l in "${LEAVES[@]}"; do harvest_node "$T" "$l" "$DIR/$l/result.log"; done
done

for l in "${LEAVES[@]}"; do mark_empty_leaves all "$DIR/$l/result.log"; done
rollup "$DIR/result.log" test "$DIR"/*/result.log
rc=$?
statuses_to_csv "$DIR/result.log" "$ROOT/results/data/test_summary.csv"
exit $rc
