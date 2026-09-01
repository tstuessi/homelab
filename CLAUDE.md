# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A GitOps repo for a personal k3s homelab cluster (domain: `k8s.tstuessi.com`), managed via ArgoCD using the app-of-apps pattern. Everything in the cluster, including ArgoCD itself, is declared here and reconciled from `main` on `git@github.com:tstuessi/homelab.git` (private repo).

## Commands

- `task apply` — `kubectl apply -f .` (defined in `Taskfile.yaml`, uses [go-task](https://taskfile.dev)).
- `task bootstrap`, `task secrets:edit`, `task secrets:rotate-deploy-key`, `task secrets:rotate-age-key`, `task hooks:install` — see Secrets management below.
- There is no build, lint, or test tooling in this repo — it's pure Kubernetes YAML/Kustomize manifests, validated by applying them.

## Architecture: app-of-apps flow

```
bootstrap/root-app.yaml   (applied manually once, out-of-band)
  -> app-of-apps/         (an ArgoCD Application per top-level concern)
       -> infrastructure/argocd    (installs ArgoCD itself, from the upstream install.yaml)
       -> infrastructure/traefik   (patches k3s's built-in Traefik via HelmChartConfig)
       -> infrastructure/debug     (throwaway whoami test workload)
```

- `bootstrap/root-app.yaml` is the entry point: an ArgoCD `Application` pointing at `app-of-apps/`, with `automated: {prune: true, selfHeal: true}`. It is applied by hand (`kubectl apply -f bootstrap/root-app.yaml`) against a cluster that already has ArgoCD running — this is the one manual step that starts the self-managing GitOps loop.
- `app-of-apps/*.yaml` are ArgoCD `Application` resources, one per subtree of `infrastructure/`. Adding a new top-level component means adding both the `infrastructure/<name>/` manifests and a matching `app-of-apps/<name>.yaml` Application pointing at that path.
- Each `infrastructure/<name>/` directory is a `kustomization.yaml` plus its resources. `infrastructure/argocd` notably installs ArgoCD by referencing the upstream `argoproj/argo-cd` `install.yaml` directly as a remote resource and patching `argocd-cmd-params-cm` (`server.insecure: "true"`, since TLS terminates at Traefik).
- Ingress is via Traefik's `IngressRoute` CRD (k3s's bundled Traefik, configured through the `helm.cattle.io/v1` `HelmChartConfig` resource in `infrastructure/traefik`), not the standard `Ingress` resource.
- All `Application.spec.destination.server` values use the in-cluster API (`https://kubernetes.default.svc`); everything runs in the same cluster ArgoCD lives in.

## Secrets management

Secrets that need to live in git (e.g. the ArgoCD GitHub deploy key) are
encrypted with [sops](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age),
under `bootstrap/secrets/`. `.sops.yaml` at the repo root scopes encryption
to that path and to just the `data`/`stringData` fields, so the rest of
each manifest stays readable in git. The age private key is intentionally
kept out of this repo (default location `~/.config/sops/age/keys.txt`) —
see `bootstrap/README.md` for the full recovery procedure and key rotation.

A git pre-commit hook (`scripts/pre-commit.sh`, installed via
`task hooks:install`) blocks commits that would add an unencrypted file
under `bootstrap/secrets/` or any staged file containing raw private key
material.

`task bootstrap` is the one-time manual step for a fresh cluster, in order:
create the `argocd` namespace, decrypt and apply the repo-credentials
secret into it, install ArgoCD directly, wait for the repo-server to be
ready (confirming it can use the credential), then apply
`bootstrap/root-app.yaml` to hand control to ArgoCD. The secret must exist
before ArgoCD starts, and ArgoCD's repo connection must be confirmed
working before the root app is applied.

## Working conventions

- Since this repo is applied straight to a live personal cluster, prefer editing/adding manifests directly over introducing templating layers (Helm charts, jsonnet, etc.) unless a component specifically needs it — the existing pattern is plain Kustomize.
- `syncPolicy.automated` is set with `prune: true` and `selfHeal: true` throughout — deleting a resource from git will delete it from the cluster on next sync, and manual `kubectl` changes to ArgoCD-managed resources get reverted.
- Since we are using SSH auth, repositories should be referenced via `git@github.com:tstuessi/<repository_name>`
