# homelab

GitOps repo for a personal k3s homelab cluster (`k8s.tstuessi.com`), managed
end-to-end by [ArgoCD](https://argo-cd.readthedocs.io/) using the
app-of-apps pattern. Everything in the cluster — including ArgoCD itself —
is declared here and reconciled from `main` on
`https://forgejo.k8s.tstuessi.com/tstuessi/homelab.git`.

See [`CLAUDE.md`](CLAUDE.md) for the detailed architecture writeup used to
brief AI coding assistants on this repo; this README is the human-facing
summary.

## How it's structured

```
bootstrap/root-app.yaml   (applied manually once, out-of-band)
  -> app-of-apps/                  (one ArgoCD Application per top-level concern)
       -> infrastructure/argocd              (installs ArgoCD itself)
       -> infrastructure/traefik             (patches k3s's built-in Traefik)
       -> infrastructure/csi-driver-smb       (SMB CSI driver + a share PV/PVC)
       -> infrastructure/ext-postgres-operator (shared Postgres operator, via Helm)
       -> infrastructure/monitoring           (kube-prometheus-stack via Helm + Grafana route)
       -> infrastructure/forgejo              (self-hosted git server — hosts this repo)
       -> infrastructure/paperless-ngx        (document management)
       -> infrastructure/romm                 (ROM manager)
       -> infrastructure/debug                (throwaway whoami/test-db workload)
       -> (external) fullstack-example repo   (app-of-apps/fullstack-example.yaml)
```

- **`bootstrap/root-app.yaml`** is the one manual step: an ArgoCD
  `Application` pointing at `app-of-apps/`, with automated prune +
  self-heal. Applying it against a cluster that already has ArgoCD running
  hands control to GitOps from then on.
- **`app-of-apps/*.yaml`** are ArgoCD `Application` resources, one per
  subtree of `infrastructure/` (plus `fullstack-example.yaml`, which points
  at a separate repo). Adding a new top-level component means adding both
  `infrastructure/<name>/` and a matching `app-of-apps/<name>.yaml`.
- Each `infrastructure/<name>/` is plain Kustomize (a `kustomization.yaml`
  plus its resources) — no Helm charts or templating layers, except where
  a component pulls an upstream chart directly (`monitoring`,
  `ext-postgres-operator`).
- Ingress is via Traefik's `IngressRoute` CRD (k3s's bundled Traefik,
  tuned through a `HelmChartConfig` in `infrastructure/traefik`), not the
  stock `Ingress` resource.
- Databases for apps (forgejo, paperless-ngx, romm, debug) are provisioned
  as `Postgres` CRDs handled by the `ext-postgres-operator`
  (movetokube/postgres-operator) against one shared Postgres instance,
  rather than each app running its own database.
- Everything runs in the same cluster ArgoCD lives in — every
  `Application.spec.destination.server` is the in-cluster API
  (`https://kubernetes.default.svc`).

## What's running

| Component | Purpose |
|---|---|
| `argocd` | ArgoCD itself, installed from the upstream manifest |
| `traefik` | Ingress controller config + dashboard route |
| `csi-driver-smb` | CSI driver for mounting an SMB share as cluster storage, plus a shared PV/PVC |
| `ext-postgres-operator` | Operator that provisions per-app Postgres databases/users on a shared instance |
| `monitoring` | kube-prometheus-stack (Prometheus + Grafana) |
| `forgejo` | Self-hosted git server — hosts this repo and others |
| `paperless-ngx` | Document management |
| `romm` | ROM manager |
| `debug` | Throwaway `whoami` workload + a test database, for poking at the cluster |

## Commands

- `task apply` — `kubectl apply -f .`
- `task bootstrap` — one-time bootstrap of a fresh cluster (see below)
- `task secrets:edit -- <file>` — edit a sops-encrypted secret in place
- `task secrets:apply -- <file>` — decrypt and apply a secret ArgoCD doesn't manage
- `task secrets:rotate-deploy-key` — rotate the deploy key ArgoCD uses to clone this repo
- `task secrets:rotate-age-key` — rotate the age keypair used to encrypt secrets
- `task fmt:yaml` — reformat all non-secret YAML to 2-space indent
- `task hooks:install` — install the git pre-commit hook that blocks committing unencrypted secrets

There's no build, lint, or test tooling — this is pure Kubernetes
YAML/Kustomize, validated by applying it.

## Secrets management

Secrets that need to live in git (deploy keys, app credentials, SMB
creds, etc.) are encrypted with [sops](https://github.com/getsops/sops) +
[age](https://github.com/FiloSottile/age) under `bootstrap/secrets/`.
`.sops.yaml` scopes encryption to that path and to just the
`data`/`stringData` fields, so the rest of each manifest stays readable in
git. The age private key is kept out of this repo (default location
`~/.config/sops/age/keys.txt`) — see [`bootstrap/README.md`](bootstrap/README.md)
for the full recovery procedure and key rotation.

A git pre-commit hook (`scripts/pre-commit.sh`, installed via
`task hooks:install`) blocks commits that would add an unencrypted file
under `bootstrap/secrets/` or any staged file containing raw private key
material.

## Bootstrapping a fresh cluster

See [`bootstrap/README.md`](bootstrap/README.md) for the full procedure.
In short, `task bootstrap`:

1. Creates the `argocd` namespace.
2. Decrypts and applies the repo-credentials secret into it.
3. Installs ArgoCD directly (`infrastructure/argocd`).
4. Waits for `argocd-repo-server` to be ready, confirming it can reach the
   private repo.
5. Applies `bootstrap/root-app.yaml`, handing control to ArgoCD, which
   syncs everything else.

## Working conventions

- Prefer editing/adding manifests directly over introducing templating
  layers — the existing pattern is plain Kustomize, unless a component
  specifically needs Helm.
- `syncPolicy.automated` is set with `prune: true` and `selfHeal: true`
  throughout: deleting a resource from git deletes it from the cluster on
  next sync, and manual `kubectl` changes to ArgoCD-managed resources get
  reverted.
- See [`docs/ADOPT_EXISTING_DB.md`](docs/ADOPT_EXISTING_DB.md) for notes on
  adopting an existing Postgres database into this IaC setup.
