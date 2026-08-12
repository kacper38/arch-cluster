# Working agreement — arch-cluster

- GitOps only: git is the change record; `kubectl apply` is break-glass. The
  cluster that consumes this repo is **pierun's k3s** (`ssh kacper@pierun`,
  then `export KUBECONFIG=$HOME/.kube/config`) — the Mac's default kubectl
  context (orbstack) is a legacy cluster on a different repo; never trust it.
- Secrets: SOPS/age only, encrypted files named `*.sops.yaml`; never commit or
  `kubectl create` plaintext secrets. A workload referencing a Secret ships in
  the same commit as that Secret (atomic enable, keeps `wait: true` green).
- Images are hand-pinned with a "verified <date>" comment. Keep the hardened
  securityContext pattern from `apps/staging/monitoring/` (runAsNonRoot with
  explicit numeric UID, readOnlyRootFilesystem, drop ALL, RuntimeDefault,
  automountServiceAccountToken: false unless the pod needs the API).
- Every app dir carries a README with owner steps (in security-relevant order)
  and failure modes. Decisions go to `DECISIONS.md`; system shape to
  `docs/SYSTEM.md`.
- Host-level 24/7 state is Ansible (`ansible/`, run with `-K` — no
  passwordless sudo on pierun). k3s itself + native `hlsc` cloudflared are
  manual-for-now (open TODO).
- CI (`.github/workflows/validate.yml`): kustomize build → kubeconform
  `-strict -skip Secret`, plaintext-Secret grep, ansible-lint (advisory).
  Anything committed must keep it green.

## Task assumptions — dashboard (2026-08)

- Glance on `dash.kacperhomelab.org` via the EXISTING remote-managed tunnel
  (`pierun-k8s`), gated by Cloudflare Access; Access policy is created BEFORE
  the public hostname (claim-before-expose, as with Kuma).
- Pi-hole is a separate LAN device in `192.168.178.0/24` (IP TBD).
- CVE report = `arch-audit` on pierun via systemd timer (Ansible-managed),
  published as JSON for a Glance `custom-api` widget. No trivy for now.
- News sources default to HN + a small RSS list; owner adjusts in `glance.yml`.
