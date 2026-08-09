#!/usr/bin/env bash
set -euo pipefail

# Snapshot of pierun's host-level config: explicit packages, enabled services,
# hand-edited /etc files. Run from the workstation: ./capture.sh
# Requires key-auth SSH to "pierun" (see ~/.ssh/config).
#
# Secrets are deliberately excluded: cloudflared tunnel credentials (*.json),
# k3s kubeconfig (k3s.yaml) and service env (*.env). A grep safety net below
# aborts if anything secret-shaped lands in the snapshot anyway.

HOST=${1:-pierun}
OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ssh "$HOST" pacman -Qqe > "$OUT/packages.txt"
ssh "$HOST" pacman -Qqm > "$OUT/packages-aur.txt"
ssh "$HOST" 'systemctl list-unit-files --state=enabled --no-legend' \
  | awk '{print $1}' > "$OUT/services-enabled.txt"
{
  echo "kernel:      $(ssh "$HOST" uname -r)"
  echo "k3s:         $(ssh "$HOST" 'k3s --version | head -1')"
  echo "cloudflared: $(ssh "$HOST" 'cloudflared --version 2>&1 | head -1')"
} > "$OUT/versions.txt"

rm -rf "$OUT/etc"
ssh "$HOST" 'tar -C / -cf - --ignore-failed-read \
    --exclude="*.json" --exclude="*.env" --exclude="k3s.yaml" \
    etc/ssh/sshd_config etc/ssh/sshd_config.d \
    etc/systemd/network \
    etc/systemd/system/k3s.service \
    etc/systemd/system/cloudflared.service \
    etc/cloudflared \
    etc/ufw/ufw.conf etc/ufw/user.rules etc/ufw/user6.rules \
    2>/dev/null' | tar -x -C "$OUT"

if grep -rIlE 'PRIVATE KEY|BEGIN CERTIFICATE|(secret|token|password)["'"'"' ]*[:=]["'"'"' ]*[A-Za-z0-9+/_-]{8,}' "$OUT/etc" 2>/dev/null; then
  echo "UWAGA: powyższe pliki wyglądają na sekrety — usunięte ze snapshotu." >&2
  grep -rIlE 'PRIVATE KEY|BEGIN CERTIFICATE|password|token' "$OUT/etc" | xargs rm -f
  exit 1
fi

echo "Snapshot OK: $OUT"
