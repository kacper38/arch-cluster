# arch-cluster

GitOps source of truth for the **pierun** homelab: a k3s cluster on an Arch Linux
laptop (`pierun`, LAN `192.168.178.55`), reconciled by [Flux](https://fluxcd.io/),
plus the Ansible config that keeps the host itself running 24/7.

Flux applies `./clusters/staging` from `main` (prune enabled, 10 min interval).
**Merge to `main` = deploy.** Nothing is `kubectl apply`'d by hand.

## Layout

| Path | What it is |
|---|---|
| `clusters/staging/` | Flux entrypoint: `flux-system/` bootstrap manifests plus the `infrastructure` and `apps` Kustomization CRs that fan out to the layers below |
| `infrastructure/` | Cluster controllers layer (ingress, operators, …) — empty for now |
| `apps/staging/` | Workloads. First app: `monitoring/` — Uptime Kuma exposed via Cloudflare Tunnel |
| `ansible/` | Host configuration for pierun's 24/7 duty (lid/suspend, Wi-Fi powersave, kubeconfig for kacper) |
| `hosts/pierun/` | Captured snapshot of the host's live config (`capture.sh` output) — reference, not applied |
| `docs/` | Runbooks and notes |
| `.sops.yaml` | sops policy: Kubernetes Secrets are age-encrypted in-repo, decrypted by Flux in-cluster |

CI (`.github/workflows/validate.yml`) runs on every PR and push to `main`:
kustomize build + kubeconform on all three layers, a plaintext-Secret scan, and
advisory ansible-lint.

## How do I…

### Add an app

1. Create `apps/staging/<app>/` with the manifests and a `kustomization.yaml`.
2. Add one line to `apps/staging/kustomization.yaml`:

   ```yaml
   resources:
     - monitoring
     - <app>
   ```

3. Open a PR. After merge, Flux picks it up within 10 minutes — or force it:
   `flux reconcile kustomization apps --with-source`.

### Add a secret

Secrets are committed **encrypted** with [sops](https://github.com/getsops/sops) + age.
`.sops.yaml` encrypts only `data`/`stringData` (`encrypted_regex`), so metadata stays diffable.

```sh
sops --encrypt --in-place apps/staging/<app>/my-secret.sops.yaml
```

- The age **private key** lives at `~/.config/sops/age/keys.txt` (backed up in the
  password manager). It is never committed.
- The cluster decrypts via the `sops-age` Secret in `flux-system` — Flux's
  Kustomization CRs reference it as the decryption provider.
  macOS note: sops does NOT look in `~/.config/sops/age/` by default (it uses
  `~/Library/Application Support/sops/age/`), so put this in your shell profile:
  `export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"` — needed for
  `sops -d` / `sops` edits; encryption and the kubectl bootstrap work without it.
- CI fails any tracked YAML containing a plaintext `kind: Secret`.

### Change host config

Host-level 24/7 state (lid/suspend behaviour, Wi-Fi powersave, iw package,
kacper's kubeconfig copy) is Ansible, not Flux — k3s itself and the host-level
`hlsc` SSH tunnel are installed manually for now (see `docs/`); extending the
role to own them is an open TODO:

```sh
ansible-playbook -i ansible/inventory.ini ansible/site.yml -K
```

### Bootstrap from zero

1. Install k3s on the host (see `ansible/` and `docs/`).
2. `flux bootstrap github --owner=<owner> --repository=arch-cluster --branch=main --path=clusters/staging --personal`
3. Recreate the decryption key:

   ```sh
   kubectl create secret generic sops-age -n flux-system \
     --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
   ```

4. Done. Everything else reconciles from this repo.

## Day-2

```sh
flux get kustomizations -A                          # what's synced, what's failing
flux reconcile kustomization apps --with-source     # don't wait for the interval
```
