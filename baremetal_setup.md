Directions

1. Make networking durable — now, on this kernel, BMC console open.
sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg >/dev/null <<'EOF'
network: {config: disabled}
EOF
sudo tee /etc/netplan/50-cloud-init.yaml >/dev/null <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    pks-uplink:
      match:
        macaddress: "40:5b:7f:e3:d8:54"
      dhcp4: true
EOF
sudo chmod 600 /etc/netplan/50-cloud-init.yaml
sudo netplan try
Press ENTER when it confirms SSH still works.

2. Return to Ubuntu.
sudo reboot

3. Revert test via a managed entry — BMC console open.
sudo grub-reboot pks-sec-off && sudo reboot
After it boots:
cat /proc/cmdline     # ... root=PARTUUID=757cd99c-... pcache_pks=off pks_auto
uname -r              # expect: 5.18.0-rc3-00056-g27ba7abe61fc
sudo reboot           # must land back on Ubuntu

4. Install the sweep.
sudo bash /home/meilan/src/pks-thesis-env/baremetal_setup.sh

5. Arm it.
sudo grub-reboot pks-control && sudo reboot

6. Collect when it's back on Ubuntu.
sudo cat /var/lib/pks-sweep/sweep.log
sudo ls -l /var/lib/pks-sweep/transcripts/