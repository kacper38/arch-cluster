# Decision log

Format: `- <decision> — <why>; revisit if: <trigger>`

## dashboard (dash.kacperhomelab.org)

- Glance as the dashboard engine (over Homepage, Homarr) — entire config is one
  YAML in git (fits Flux/GitOps), single small Go binary, native RSS/HN/news
  widgets plus `custom-api` for everything bespoke (Kuma, pi-hole, Flux status,
  CVE report); revisit if: a widget need exceeds what `custom-api` templates
  can render.
- `dash.kacperhomelab.org` subdomain on the existing zone, NOT a new domain —
  zero cost, zero new zone config, same remote-managed tunnel; revisit if:
  the dashboard should be shareable under a non-homelab identity.
- Cloudflare Access (free tier) in front of the hostname — Flux status, package
  CVE list and pi-hole stats are recon gold; cert lands in CT logs the moment
  the hostname exists, so no unauthenticated exposure; revisit if: Access
  friction on daily use outweighs the risk (unlikely).
- CVE scope = Arch packages on pierun via `arch-audit` (host-side systemd
  timer), NOT container image scanning — it covers exactly what is installed,
  runs in milliseconds, no 600MB trivy DB; revisit if: supply-chain coverage
  of container images becomes a real concern (then: trivy CronJob).
- Pi-hole lives on a separate LAN device (192.168.178.0/24) — dashboard reaches
  it over LAN egress from the pod; revisit if: pi-hole moves into the cluster.

## monitoring (pre-existing, recorded for context)

- Uptime Kuma on node-local `local-path` PVC with prune disabled — monitor
  history is cheap to lose, cheap to recreate; revisit if: monitor count grows
  past "recreate from README" comfort.
- cloudflared has deliberately no probes — /ready reflects edge connectivity,
  a WAN blip would restart-loop the pod; revisit if: cloudflared adds a
  process-health-only endpoint.
