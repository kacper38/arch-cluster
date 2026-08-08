# Ansible — pierun host configuration

Declarative host-level configuration for `pierun` (Arch Linux laptop,
`192.168.178.55`), the k3s node of this cluster. Replaces ad-hoc shell
scripting: every setting here is idempotent, versioned, and re-appliable.

## Usage

From the repo root:

```sh
ansible-playbook -i ansible/inventory.ini ansible/site.yml -K
```

`-K` prompts for the sudo password of `ansible_user` (`kacper`) at run
time; nothing stores it. Re-running the playbook is safe — unchanged
settings report `ok`, not `changed`.

## What the `host-24-7` role changes, and why

The laptop must keep serving k3s 24/7 with the lid closed:

| Change | Why |
| --- | --- |
| Logind drop-in `/etc/systemd/logind.conf.d/laptop-server.conf` (`HandleLidSwitch*=ignore`, `IdleAction=ignore`) | Closing the lid or being idle must not suspend the node. Applied via `systemctl kill -s HUP systemd-logind` — a restart would drop active sessions. |
| Mask `sleep.target`, `suspend.target`, `hibernate.target`, `hybrid-sleep.target` | Belt-and-suspenders: no code path (power keys, DE, dbus) can put the host to sleep. |
| Install `iw` (pacman) | Needed to control Wi-Fi power management; not present on the host by default. |
| Udev rule `/etc/udev/rules.d/81-wifi-powersave.rules` + immediate `iw dev wlan0 set power_save off` | Wi-Fi power save causes latency spikes and dropped connections on an iwd + systemd-networkd headless host. The udev rule makes it survive reboots and interface re-adds; the immediate task fixes the running system (only when the current state is `on`). |
| `/etc/rancher/k3s/k3s.yaml` → `/home/kacper/.kube/config` (owner `kacper`, mode `0600`) | The k3s kubeconfig is root-only; this gives `kacper` kubectl access without sudo. |

Battery charge capping is intentionally **not** configured: `BAT1` on this
machine exposes no `charge_control_end_threshold` sysfs knob.

## What Ansible cannot do

**BIOS "Restore on AC Power Loss"** must be enabled by hand in firmware
setup — it is the only way the node comes back after a power cut drains
the battery. Ansible has no access to BIOS settings.

## Post-run verification checklist

1. Close the lid, wait 10 minutes → SSH to `192.168.178.55` still works.
2. `iw dev wlan0 get power_save` → `Power save: off`.
3. Full reboot, then `systemctl status k3s` → `active (running)`.
