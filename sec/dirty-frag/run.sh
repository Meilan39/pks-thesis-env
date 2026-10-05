#!/usr/bin/env bash
set -u

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# 1. Semantically Static Constants
TARGET_FILE="/mnt/protected/victim_file"
EXPLOIT_BIN="./exp"
EXPLOIT_SRC="./exp.c"
CLEAN_MARKER="PKS_CLEAN_MARKER_dirty-frag_DO_NOT_OVERWRITE"

# 2. Precondition Checks
[ "$(id -u)" -eq 0 ]    || { echo "error: root privileges required"; exit 1; }
id testuser &>/dev/null || { echo "error: testuser account required"; exit 1; }
[ -d "/mnt/protected" ] || { echo "error: /mnt/protected not mounted"; exit 1; }
[ -x "$EXPLOIT_BIN" ]   || gcc -O2 -Wall -pthread -o "$EXPLOIT_BIN" "$EXPLOIT_SRC" || { echo "error: build failed"; exit 1; }

# 3. Target Preparation
printf '%s\n' "$CLEAN_MARKER" > "$TARGET_FILE"
head -c 4096 /dev/zero >> "$TARGET_FILE" 2>/dev/null || true
chmod 644 "$TARGET_FILE"
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
cat "$TARGET_FILE" > /dev/null 2>&1 || true

# 4. Exploit Execution
su -s /bin/bash testuser -c "'$EXPLOIT_BIN'" || true

# 5. Memory Inspection
if grep -qF "$CLEAN_MARKER" <(head -c 256 "$TARGET_FILE" 2>/dev/null); then
    echo "marker=intact"
else
    echo "marker=altered"
fi


