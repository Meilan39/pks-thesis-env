#!/usr/bin/env bash

# =============================================================================
# PKS unattended sweep — INSTALLER (run once as root; does NOT reboot)
#   sudo bash /home/meilan/src/pks-thesis-env/baremetal_setup.sh
# Safe to re-run: every step overwrites or is guarded. Arming is a SEPARATE
# step (sudo grub-reboot pks-control && sudo reboot) you run when ready.
# Pre-reqs already done: §7 GRUB entries installed, /dev/loop8 ext4 eval device.
# Run the §7d revert test BEFORE this installer (see the notes I gave you):
# once the queue exists, any pks_auto boot triggers the sweep.
# =============================================================================
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo bash $0"; exit 1; }

# 1. Unprivileged account the sec exploits run as (NOT uid 1000 == meilan)
id testuser &>/dev/null || useradd -m -s /bin/bash testuser
echo "testuser: $(id testuser)"

# 2. The boot-chained runner
cat > /usr/local/bin/pks-sweep.sh <<'SWEEP_EOF'
#!/usr/bin/env bash
set -euo pipefail
REPO="$HOME_REPO"
STATE=/var/lib/pks-sweep
QUEUE="$STATE/queue"
LOG="$STATE/sweep.log"
mkdir -p "$STATE/transcripts"

if [ -e "$STATE/STOP" ]; then
    echo "$(date -Is) STOP present; parking on default kernel" >> "$LOG"
    rm -f "$QUEUE"; systemctl reboot; exit 0
fi
[ -s "$QUEUE" ] || { echo "$(date -Is) queue empty; sweep complete" >> "$LOG"; systemctl reboot; exit 0; }

read -r variant mode grub_id target _ < "$QUEUE"
echo "$(date -Is) running $variant/$mode ($target)" >> "$LOG"

transcript="$STATE/transcripts/${variant}-${mode}-${target//\//-}.transcript"
EXECUTOR=baremetal PROTECTED_DEV="${PROTECTED_DEV:-/dev/loop8}" \
    "$REPO/exec/baremetal.sh" "$variant" "$mode" "$target" "$transcript" \
    >> "$LOG" 2>&1 || echo "$(date -Is) run returned non-zero (continuing)" >> "$LOG"
sync

tail -n +2 "$QUEUE" > "$QUEUE.next" && mv "$QUEUE.next" "$QUEUE"
if [ -s "$QUEUE" ]; then
    read -r _v _m next_id _ < "$QUEUE"
    grub-reboot "$next_id"
    echo "$(date -Is) next boot -> $next_id" >> "$LOG"
else
    echo "$(date -Is) last config done; no one-shot set -> default (Ubuntu) next" >> "$LOG"
fi
systemctl reboot
SWEEP_EOF
chmod 755 /usr/local/bin/pks-sweep.sh
echo "installed /usr/local/bin/pks-sweep.sh"

# 3. The unit (pre-filled: repo path + /dev/loop8; ordered after the loop attaches)
cat > /etc/systemd/system/pks-sweep.service <<'UNIT_EOF'
[Unit]
Description=PKS bare-metal evaluation sweep (boot-chained)
After=multi-user.target network-online.target pks-eval-loop.service
Wants=pks-eval-loop.service
ConditionKernelCommandLine=pks_auto
ConditionPathExists=/var/lib/pks-sweep/queue

[Service]
Type=oneshot
Environment=HOME_REPO=/home/meilan/src/pks-thesis-env
Environment=PROTECTED_DEV=/dev/loop8
ExecStart=/usr/local/bin/pks-sweep.sh
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
UNIT_EOF
echo "installed /etc/systemd/system/pks-sweep.service"

# 4. Hardware watchdog (recommended for unattended): resets the box on a hard hang
#    with no panic. systemd skips silently if the kernel exposes no /dev/watchdog.
mkdir -p /etc/systemd/system.conf.d
printf '[Manager]\nRuntimeWatchdogSec=60\n' > /etc/systemd/system.conf.d/pks-watchdog.conf
echo "installed watchdog drop-in (RuntimeWatchdogSec=60)"

# 5. Register the unit + write the matrix queue (order = run order)
systemctl daemon-reload
systemctl enable pks-sweep.service
mkdir -p /var/lib/pks-sweep
# Full matrix (8 boots): sec control/off/on, compliance off/on, perf control/off/on.
# One axis per boot (exec/baremetal.sh takes a single target), so a kernel that
# serves two axes is booted twice; grouped by kernel to keep that obvious.
tee /var/lib/pks-sweep/queue >/dev/null <<'Q_EOF'
control control pks-control  sec
control control pks-control  perf
sec     off     pks-sec-off  test
sec     off     pks-sec-off  sec
sec     on      pks-sec-on   test
sec     on      pks-sec-on   sec
perf    off     pks-perf-off perf
perf    on      pks-perf-on  perf
Q_EOF

echo
echo "=== installed, NOT armed. queue: ==="
cat /var/lib/pks-sweep/queue
echo
echo "Enabling now is safe: the service is inert on ordinary Ubuntu boots"
echo "(it needs BOTH pks_auto on the cmdline AND the queue file)."
echo "Arm it when ready with:  sudo grub-reboot pks-control && sudo reboot"
