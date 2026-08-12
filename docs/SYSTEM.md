# System description — arch-cluster

One page. Auditors and future-me read this first. Keep current at every release.

## Purpose

GitOps-managed single-node homelab: k3s on `pierun` (Arch Linux laptop, 24/7,
lid closed), reconciled by Flux from this repo. Everything reaches the internet
outbound-only through Cloudflare Tunnels — no inbound ports on the home network.

## Components & data flows

| Component | Where | Flow |
|---|---|---|
| Flux v2.7.5 (4 controllers) | `flux-system` ns | pulls `github.com/kacper38/arch-cluster` (main, 1m) → applies `clusters/staging` → `infrastructure` (empty placeholder) → `apps/staging` |
| Uptime Kuma 2.4.0 | `monitoring` ns | SQLite on 1Gi local-path PVC (prune-disabled); serves `status.kacperhomelab.org` via tunnel |
| cloudflared connector | `monitoring` ns | outbound to Cloudflare edge (7844/443); routes public hostnames → in-cluster ClusterIP services; egress pinned by NetworkPolicy |
| Dashboard (Glance) — planned | `dashboard` ns | serves `dash.kacperhomelab.org` behind Cloudflare Access; reads Kuma, pi-hole (LAN device), kube API (Flux status), RSS/HN, arch-audit CVE report |
| arch-audit timer — planned | pierun host (Ansible) | Arch Security Tracker → JSON report → consumed by dashboard |
| Native cloudflared (`hlsc`) | pierun host (systemd) | separate tunnel: `ssh.kacperhomelab.org` → localhost:22; NOT GitOps-managed (open TODO: Ansible) |
| host_24_7 Ansible role | pierun host | lid/suspend behaviour, Wi-Fi powersave, kacper's kubeconfig copy |

## Environments

Single environment: `staging` (naming headroom, no prod split). One node, one
cluster. The Mac's local orbstack cluster is legacy (tracks the predecessor
repo Mack8sCluster) and is NOT part of this system.

## Interfaces

- Inbound (all via Cloudflare tunnels, no open ports): `status.` (Kuma),
  `ssh.` (host SSH), `dash.` (planned, behind CF Access).
- Outbound: Flux→GitHub (https), cloudflared→CF edge, Kuma→monitored targets,
  dashboard→LAN pi-hole + feeds (planned), arch-audit→security.archlinux.org.

## Secrets & data classification

- Secrets in git are SOPS/age-encrypted only (CI greps for plaintext
  `kind: Secret`); decrypted in-cluster via the `sops-age` Secret — the single
  manually-created secret; age private key backed up in the password manager.
- Data: monitoring history (low value, recreatable), tunnel tokens & pi-hole
  credentials (secret), CVE/package inventory (sensitive-ish: recon value —
  hence Access-gated dashboard).
