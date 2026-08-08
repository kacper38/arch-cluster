# monitoring — Uptime Kuma + Cloudflare Tunnel

First application on the cluster. Lives under `apps/staging/monitoring/` and is
applied by the **`apps` Flux Kustomization CR** (`clusters/staging/apps.yaml`:
path `./apps/staging`, interval 10m, prune enabled, `wait: true` — so
`flux get kustomizations` honestly reports app readiness, not just "applied").
`apps` depends on the `infrastructure` CR; both are reconciled from `main` by
the bootstrap Kustomization (`clusters/staging/flux-system/`, path
`./clusters/staging`) once merged **and** pierun is powered on. No
`kubectl apply` needed — git is the change record; hand-applying is
break-glass only.

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
- **Tunnel token** (`cloudflared-token.sops.yaml`, once created) — SOPS-encrypted
  Secret in git, decrypted in-cluster by Flux. NOT `kubectl`-created.

## One-time cluster bootstrap (before anything SOPS-encrypted can deploy)

Create the age decryption key Secret for Flux — run from the laptop, against
pierun. This is the **only** manually-created Secret on the cluster; everything
else flows through git:

```bash
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
```

The age **private** key is backed up in the password manager — if pierun is
reinstalled, restore `keys.txt` from there and re-run this command. The public
key (recipient) lives in the repo-root `.sops.yaml`.

## One-time owner steps (in order — the order is security-relevant)

1. **Create the tunnel** — Cloudflare Zero Trust dashboard → Networks → Tunnels →
   Create tunnel → **remote-managed** (Cloudflared connector) → name: `pierun-k8s`.
   Copy the tunnel token (long `eyJ...` string). Do NOT add a Public Hostname yet.

2. **Encrypt the token into git** (the Secret is SOPS-managed, never
   `kubectl`-created). Write `apps/staging/monitoring/cloudflared-token.yaml`:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: cloudflared-token
     namespace: monitoring
   stringData:
     token: <TOKEN>
   ```

   Then encrypt it, delete the plaintext, and wire it in:

   ```bash
   cd apps/staging/monitoring
   sops --encrypt cloudflared-token.yaml > cloudflared-token.sops.yaml
   rm cloudflared-token.yaml
   ```

   Uncomment BOTH commented lines in this directory's `kustomization.yaml`
   (`- cloudflared.yaml` AND `- cloudflared-token.sops.yaml`) in the same
   commit, then merge. This is the atomic tunnel enable: the connector and its
   Secret always deploy together, so the `apps` Kustomization (wait: true)
   stays green the whole time and no CreateContainerConfigError window exists.
   Flux decrypts in-cluster via the `sops-age` Secret (see bootstrap above) —
   the plaintext token never lands in git.

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
  - *"secret \"cloudflared-token\" not found"* — expected before the encrypted
    token (step 2) is merged and reconciled; self-heals once it is.
  - *"container has runAsNonRoot and image has non-numeric user"* — the
    `runAsUser: 65532` pin was removed from the manifest; restore it. This one
    NEVER self-heals and must not be waited out.
- **`apps` Kustomization stuck on a decryption error** (`flux get kustomizations`
  shows it failed) — the `sops-age` Secret is missing/wrong in `flux-system`, or
  the file was encrypted to a different age recipient than `.sops.yaml` pins.
  Re-run the bootstrap step with the backed-up key.
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
