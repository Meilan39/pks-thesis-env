#!/usr/bin/env bash
# ==============================================================================
# sec/fragnesia/run.sh - Softirq/workqueue page-cache write neutralization
# ==============================================================================
# Builds the PoC if needed, seeds a marker in the protected victim file, drops
# caches to force a real page-cache re-fault, runs it as testuser, and reports
# whether the marker survived. Under on each store of the workqueue decrypt loop
# is suppressed by advancing the instruction pointer past it, without crashing
# the system, keeping the marker intact; under off the marker is overwritten.
# ==============================================================================
set -u

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------
TARGET_FILE="/mnt/protected/victim_file"
EXPLOIT_BIN="./exp"
EXPLOIT_SRC="./exp.c"
CLEAN_MARKER="PKS_CLEAN_MARKER_fragnesia_DO_NOT_OVERWRITE"

# ------------------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ]    || { echo "error: root privileges required"; exit 1; }
id testuser &>/dev/null || { echo "error: testuser account required"; exit 1; }
[ -d "/mnt/protected" ] || { echo "error: /mnt/protected not mounted"; exit 1; }
[ -x "$EXPLOIT_BIN" ]   || gcc -O2 -Wall -pthread -o "$EXPLOIT_BIN" "$EXPLOIT_SRC" || { echo "error: build failed"; exit 1; }

# ------------------------------------------------------------------------------
# Prepare victim file
# ------------------------------------------------------------------------------
printf '%s\n' "$CLEAN_MARKER" > "$TARGET_FILE"
head -c 65536 /dev/zero >> "$TARGET_FILE" 2>/dev/null || true
chmod 644 "$TARGET_FILE"
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
cat "$TARGET_FILE" > /dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# Verify the seed BEFORE attacking
# ------------------------------------------------------------------------------
# The three sec leaves share one victim file and run in one boot, each re-seeding
# it with its own marker. If this leaf's re-seed did not reach the folio the
# inspection reads (a stale page-cache folio, or a failed protected-mount write),
# the file still holds the PREVIOUS leaf's marker -- which shares the
# "PKS_CLEAN_MARKER_" prefix, so the PoC's byte-0 check still sees 'P' and reports
# changed=0, while the full-string check below fails and would mis-score a clean
# kernel as "altered". Report that as a harness fault, not a security outcome.
if ! grep -qF "$CLEAN_MARKER" <(head -c 256 "$TARGET_FILE" 2>/dev/null); then
    echo "seed=failed"
    echo "marker=unresolved"
    exit 1
fi
echo "seed=ok"

# ------------------------------------------------------------------------------
# Run exploit
# ------------------------------------------------------------------------------
su -s /bin/bash testuser -c "'$EXPLOIT_BIN'" || true

# ------------------------------------------------------------------------------
# Inspect marker
# ------------------------------------------------------------------------------
# Record the actual bytes so a verdict is never a bare word, and separate a real
# payload injection from mere collateral corruption: the PoC's shell payload
# begins with the ELF magic 7f 45 4c 46, so its presence at offset 0 is the only
# proof the attacker's CHOSEN bytes landed. "corrupted" means the payload was
# blocked (the security property held) but the original bytes were not preserved.
echo "[evidence] fragnesia victim first 64 bytes after exploit:"
head -c 64 "$TARGET_FILE" 2>/dev/null | od -An -tx1 || true
magic="$(head -c 4 "$TARGET_FILE" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
if grep -qF "$CLEAN_MARKER" <(head -c 256 "$TARGET_FILE" 2>/dev/null); then
    echo "integrity=preserved"
    echo "marker=intact"
elif [ "$magic" = "7f454c46" ]; then
    echo "integrity=injected"
    echo "marker=altered"
else
    echo "integrity=corrupted"
    echo "marker=altered"
fi
