1. Re-install the runner + regenerate the queue (idempotent; does not reboot):
sudo bash /home/meilan/src/pks-thesis-env/baremetal_setup.sh
Confirm it printed the 8-line queue.

2. Make sure the eval loop device is attached (the sweep's unit waits on it, but check):
sudo systemctl start pks-eval-loop.service
lsblk /dev/loop8 && cat /var/lib/pks-sweep/queue

3. (Recommended) clear old sweep state so this run is clean-provenance:
sudo rm -f /var/lib/pks-sweep/sweep.log
sudo rm -rf /var/lib/pks-sweep/transcripts && sudo mkdir -p /var/lib/pks-sweep/transcripts

4. Arm and launch (boots the first queued config, then walks the matrix on its own):
sudo grub-reboot pks-control && sudo reboot

5. When it's back on Ubuntu, the sweep is done. Verify all 8 transcripts landed:
grep -a '^20' /var/lib/pks-sweep/sweep.log | tail        # should end "...default (Ubuntu) next"
ls -l /var/lib/pks-sweep/transcripts/                     # expect 8 *.transcript
Expected files: control-control-sec, control-control-perf, sec-off-test, sec-off-sec, sec-on-test, sec-on-sec, perf-off-perf, perf-on-perf.

▎ If a leaf wedged, that boot's one-shot was already consumed, so you land on Ubuntu with that config's transcript missing. Re-arm just that config with sudo grub-reboot <id> && sudo reboot, then run its exec/baremetal.sh … <transcript> by hand (§9 of the setup doc).

---

Step-by-step: push the data to the repo

The transcripts are root-owned under /var/lib/pks-sweep. We copy them into the repo under a date+provenance folder (so they never collide with the stale QEMU results and are ready for your manual processing later). Run from Ubuntu as meilan:

6. Stage the raw dataset into the repo:
cd /home/meilan/src/pks-thesis-env
DEST="results/baremetal/$(date +%F)-inawashiro"
mkdir -p "$DEST"
sudo cp /var/lib/pks-sweep/transcripts/*.transcript /var/lib/pks-sweep/sweep.log "$DEST"/
sudo cp results/preflight.json "$DEST"/ 2>/dev/null || true   # provenance, if present