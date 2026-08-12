# dashboard — Glance devops control plane

Personal dashboard at `dash.kacperhomelab.org`, gated by **Cloudflare Access**
(the content — Flux state, CVE list, Pi-hole stats — is recon gold; it is
never exposed unauthenticated). Applied by the `apps` Flux Kustomization like
everything else under `apps/staging/`.

Components:

- **Glance** (`glance.yaml` + `glance.yml`) — the dashboard.
  `glanceapp/glance:v0.8.5`, stateless; whole config is `glance.yml` in git,
  shipped as a hash-suffixed ConfigMap (`configMapGenerator`), so every config
  change rolls the pod — Glance's built-in file-watch does NOT survive
  ConfigMap symlink swaps, never rely on it.
- **Widgets**: service monitors, Pi-hole v6 stats (`192.168.178.53`), Flux
  Kustomization status (kube API + minted SA token), arch-audit CVE report
  (host timer → hostPath → served by Glance at `/assets/report.json`),
  HN + RSS.
- **RBAC** (`rbac.yaml`) — SA `glance` readable scope: Flux Kustomizations
  only. No gitrepositories, no secrets.
- **Secrets** (`glance-secrets.sops.yaml`) — `FLUX_SA_TOKEN` (1-year minted
  token) + `PIHOLE_PASSWORD` (Pi-hole APP password, never the admin one).
  SOPS/age in git, decrypted in-cluster by Flux.
- **NetworkPolicy** (`networkpolicy.yaml`) — pins Glance egress to DNS, Kuma,
  kube API, the Pi-hole IP, and https-internet; `cloudflared-egress` in
  `monitoring` got one extra rule allowing the tunnel → Glance:8080.

## One-time owner steps (in order — the order is security-relevant)

1. **Pi-hole app password** — `http://192.168.178.53/admin` → Settings →
   Web Interface / API → *Configure app password*. Use THAT (not the admin
   password) in the Secret. Give the Pi-hole device and pierun **DHCP
   reservations** on the router — the NetworkPolicy and widget pin their /32s.

2. **Mint the Flux-reader token** (SA ships in the scaffold commit):

   ```bash
   ssh kacper@pierun 'KUBECONFIG=$HOME/.kube/config kubectl -n dashboard create token glance --duration=8760h'
   ```

3. **Encrypt both into git** (same flow as the tunnel token):

   ```bash
   cd apps/staging/dashboard
   cat > glance-secrets.yaml <<'EOF'
   apiVersion: v1
   kind: Secret
   metadata:
     name: glance-secrets
     namespace: dashboard
   stringData:
     FLUX_SA_TOKEN: <minted token>
     PIHOLE_PASSWORD: <app password>
   EOF
   sops --encrypt glance-secrets.yaml > glance-secrets.sops.yaml
   rm glance-secrets.yaml
   ```

   The Deployment, config, Secret and NetworkPolicies ship in ONE commit
   (atomic enable — `apps` has `wait: true`).

4. **Cloudflare Access BEFORE the hostname exists** (claim-before-expose: the
   cert hits CT logs the moment the hostname is created; bots scan in
   minutes — same lesson as Kuma's README):
   1. Zero Trust → Integrations → Identity providers → add **One-time PIN**
      (not auto-enabled for newer orgs).
   2. Access → Applications → **self-hosted** app for
      `dash.kacperhomelab.org` → Allow policy, Include → Emails =
      `kacperosss38@gmail.com` (EXACT email — an "any OTP" include admits
      anyone) → session duration 1 week (longer = fewer silent widget-poll
      failures after cookie expiry).
   3. ONLY THEN: Networks → Tunnels → `pierun-k8s` → Public Hostname → add
      `dash.kacperhomelab.org` → `http://glance.dashboard.svc.cluster.local:8080`.
   4. Optional: on that route enable *Protect with Access* (connector-side
      JWT validation). Do NOT enable it on `ssh.kacperhomelab.org`.

## Failure modes (know the difference)

- **CrashLoop, log says `environment variable ... not found`** — a `${VAR}`
  referenced in `glance.yml` is missing from `glance-secrets`. Fix the Secret
  (re-encrypt, commit); this never self-heals.
- **Flux widget shows 401** — the 1-year token expired or was minted before
  the SA existed. Re-mint (owner step 2), re-encrypt, commit. Yearly chore.
- **Pod `Pending`, event mentions hostPath** — `/var/lib/arch-audit` missing
  on pierun: the Ansible play (`ansible-playbook -i ansible/inventory.ini
  ansible/site.yml -K`) never ran. Fix the host; do NOT switch the mount to
  `DirectoryOrCreate`.
- **CVE widget empty/erroring** — `report.json` stale or absent:
  `systemctl status arch-audit-report.timer` on pierun. The report has no
  timestamp field; a dead timer is otherwise invisible (accepted; candidate
  Kuma push monitor later).
- **dns-stats widget error** — Pi-hole IP changed (DHCP without reservation),
  app password revoked, or the device stopped being v6 (`curl -si
  http://192.168.178.53/api/stats/summary` — 401 JSON is healthy-v6).
- **Whole dashboard unreachable but pod healthy** — Access policy/hostname
  misconfig at Cloudflare; `curl -sI https://dash.kacperhomelab.org` should
  302 to `*.cloudflareaccess.com` when logged out.
- **Image bumps** — tag hand-pinned (`v0.8.5`, digest verified 2026-08-12,
  Docker Hub only). Keep the explicit `runAsUser: 65534` (image has no USER
  directive) or the pod dies in CreateContainerConfigError.
