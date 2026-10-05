#!/usr/bin/env bash
set -u

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# 1. Semantically Static Constants
TARGET_FILE="/mnt/protected/victim_file"
EXPLOIT_BIN="./exp"
CLEAN_MARKER="PKS_CLEAN_MARKER_31431_DO_NOT_OVERWRITE"

# 2. Precondition Checks
[ "$(id -u)" -eq 0 ]    || { echo "error: root privileges required"; exit 1; }
id testuser &>/dev/null || { echo "error: testuser account required"; exit 1; }
[ -d "/mnt/protected" ] || { echo "error: /mnt/protected not mounted"; exit 1; }
[ -f "$EXPLOIT_BIN" ]   || { echo "error: $EXPLOIT_BIN not found"; exit 1; }

# 3. Target Preparation
printf '%s\n' "$CLEAN_MARKER" > "$TARGET_FILE"
chmod 644 "$TARGET_FILE"
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

# 4. Exploit Execution
su -s /bin/bash testuser -c "python3 '$EXPLOIT_BIN'" || true

# 5. Memory Inspection
if grep -qF "$CLEAN_MARKER" <(head -c 256 "$TARGET_FILE" 2>/dev/null); then
    echo "marker=intact"
else
    echo "marker=altered"
fi


