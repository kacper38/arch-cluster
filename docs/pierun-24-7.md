# pierun as a 24/7 server (Arch laptop, lid closed)

One-time setup so the k3s node survives lid-close, stays awake unattended, and
comes back by itself after a power cut. Run everything as root on pierun.

## 1. Ignore the lid, never sleep

```bash
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/laptop-server.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF
systemctl kill -s HUP systemd-logind   # reload without dropping sessions
```

Belt and suspenders — make suspend impossible even if something requests it:

```bash
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

Verify: close the lid, wait a minute, `ssh` still answers. `systemd-inhibit --list`
should show logind no longer holding lid handlers.

## 2. Wi-Fi power save OFF (node is on wlan0)

Power save causes multi-second latency spikes and dropped tunnel connections.

```bash
# NetworkManager:
cat > /etc/NetworkManager/conf.d/wifi-powersave-off.conf <<'EOF'
[connection]
wifi.powersave = 2
EOF
systemctl restart NetworkManager

# (if using iwd/systemd-networkd instead, use an udev rule:)
# echo 'ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan*", RUN+="/usr/bin/iw dev $name set power_save off"' \
#   > /etc/udev/rules.d/81-wifi-powersave.rules
```

Long-term: a USB-Ethernet dongle or the built-in NIC beats Wi-Fi for a k8s node —
worth doing when convenient, not blocking.

## 3. Come back after a power cut

- **Firmware**: enable "Restore on AC Power Loss" / "AC Back: Power On" in
  BIOS/UEFI (the one step that can't be scripted).
- **Services**: `systemctl enable k3s` (cloudflared runs IN the cluster, so k3s
  up = tunnel up; the host-level `hlsc` SSH tunnel service should also be
  enabled: `systemctl enable cloudflared`).

## 4. Battery care (always-on-AC laptop)

Cap charge to ~80% so the permanently-plugged battery doesn't swell. If the
firmware supports it:

```bash
echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold
# persist via tlp (charge thresholds) or a tmpfiles.d/udev rule
```

If the sysfs knob doesn't exist on this hardware, skip — not critical.

## 5. Optional niceties

- `consoleblank=60` on the kernel cmdline turns the panel off (saves power,
  panel wear) without affecting anything else.
- The battery is effectively a built-in UPS — short brownouts won't touch the
  node at all.

## Verification checklist

- [ ] lid closed 10 min → node still reachable over SSH
- [ ] `systemctl status k3s` active after a full reboot with lid closed
- [ ] pull AC for 30 s with lid closed → node keeps running on battery
- [ ] (after BIOS step) cold power cut → node boots back unattended
