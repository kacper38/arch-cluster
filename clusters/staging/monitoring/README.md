# monitoring — Uptime Kuma + Cloudflare Tunnel

First application on the cluster. Flux (bootstrap in `clusters/staging/flux-system/`,
Kustomization path `./clusters/staging`, interval 10m, prune enabled) applies this
directory via the explicit root `clusters/staging/kustomization.yaml` once merged to
`main` **and** pierun is powered on. No `kubectl apply` needed — git is the change
record; hand-applying is break-glass only.

Components:

- **Uptime Kuma** (`uptime-kuma.yaml`) — status/uptime monitor, SQLite on a 1Gi
  `local-path` PVC, ClusterIP `uptime-kuma.monitoring.svc.cluster.local:3001`.
  `strategy: Recreate` is mandatory (SQLite on RWO — never two writers).
  Rootless image variant, runs as UID 1000.
- **cloudflared** (`cloudflared.yaml`) — remote-managed Cloudflare Tunnel connector.
  Outbound-only; no Ingress, no open ports on the home network.
- **NetworkPolicy** (`networkpolicy.yaml`) — pins cloudflared egress to
  Kuma + DNS + the Cloudflare edge, so a compromised Cloudflare account cannot
  route tunnels to arbitrary in-cluster services.

## One-time owner steps (in order — the order is security-relevant)

1. **Create the tunnel** — Cloudflare Zero Trust dashboard → Networks → Tunnels →
   Create tunnel → **remote-managed** (Cloudflared connector) → name: `pierun-k8s`.
   Copy the tunnel token (long `eyJ...` string). Do NOT add a Public Hostname yet.

2. **Create the token Secret on pierun** (this Secret is deliberately NOT in git):

   ```bash
   kubectl -n monitoring create secret generic cloudflared-token \
     --from-literal=token=<TOKEN>
   ```

   If Flux hasn't reconciled yet, the `monitoring` namespace won't exist —
   either wait for Flux (≤10m after merge) or `kubectl create namespace monitoring`
   first; Flux will adopt it.

3. **Claim the instance BEFORE exposing it.** A fresh Kuma has no pre-auth —
   the first visitor owns it, and the moment a Public Hostname exists the cert
   lands in Certificate Transparency logs, which bots scan within minutes. So:

   ```bash
   kubectl -n monitoring port-forward svc/uptime-kuma 3001:3001
   ```

   Open <http://localhost:3001> and create the admin account. Only then continue.

4. **Route the hostname** — in the tunnel's **Public Hostname** tab add:
   - Hostname: `status.kacperhomelab.org`
   - Service: `http://uptime-kuma.monitoring.svc.cluster.local:3001`

   The DNS record is auto-created by Cloudflare. Verify <https://status.kacperhomelab.org>
   shows the login page (not the setup wizard).

5. **Telegram notifications** — create a bot via `@BotFather` in Telegram, then in
   Kuma UI: Settings → Notifications → Add → Telegram (bot token + chat ID).
   Set it as a default notification and TEST it (the ArtEventOS reboot-cron gate
   requires alert delivery proven, not just configured).

## Monitors to create in Kuma UI

1. **HTTPS** — `https://kacperhomelab.org/api/health`, interval 60s, retries 3,
   alerts → Telegram.
2. **Push** — name `pg-backup`, grace period **26h**. The generated push URL gets
   appended to the VPS Postgres backup cron — that step lives in the ArtEventOS
   repo plan, `docs/plans/vps-update-strategy.md`.
3. **Push** — name `post-reboot` (consumed by the future Sunday reboot health
   script on the VPS).

## Failure modes (know the difference)

- **`CreateContainerConfigError` on cloudflared** has TWO distinct causes — check
  `kubectl -n monitoring describe pod <cloudflared-pod>`:
  - *"secret \"cloudflared-token\" not found"* — expected before step 2;
    self-heals once the Secret exists.
  - *"container has runAsNonRoot and image has non-numeric user"* — the
    `runAsUser: 65532` pin was removed from the manifest; restore it. This one
    NEVER self-heals and must not be waited out.
- **`CrashLoopBackOff` on cloudflared** — token invalid/revoked or Cloudflare
  unreachable; check pod logs.
- **Kuma data is node-local** — the `local-path` PV lives on pierun's disk. If
  the node dies, monitor history and Kuma config are lost. Accepted: monitors
  are cheap to recreate from this README. The PVC and Namespace carry
  `kustomize.toolkit.fluxcd.io/prune: disabled`, so a git-side delete/rename of
  this directory does NOT garbage-collect the data — decommissioning requires an
  explicit `kubectl delete`.
- **Image bumps** — both tags are hand-pinned (`louislam/uptime-kuma:2.4.0-rootless`,
  `cloudflare/cloudflared:2026.7.3`, both verified 2026-07-25). cloudflared is
  supported ~1 year per release — bump a couple times a year. When bumping, keep
  the explicit `runAsUser` pins (both images declare non-numeric USERs; see
  manifest comments).
