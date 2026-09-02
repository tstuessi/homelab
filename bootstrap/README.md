# Bootstrap / disaster recovery

Everything the cluster needs is in this repo, with one exception: the
**age private key** used to decrypt `secrets/argocd-repo-creds.yaml`. That
key is not in git on purpose — back it up somewhere durable outside this
repo (e.g. a password manager entry) before you need it.

## Rebuilding from scratch

1. Install `sops`, `age`, `kubectl`, `task`, and `yamlfmt` on the machine
   you're bootstrapping from. (`yamlfmt` is only needed to commit changes —
   its pre-commit hook enforces 2-space YAML formatting — not for the
   bootstrap steps below.)
2. Restore the age private key to `~/.config/sops/age/keys.txt` (sops'
   default lookup location) from your backup.
3. Point `kubectl` at the new cluster.
4. Run `task bootstrap`. This will, in order:
   - Create the `argocd` namespace (the upstream install manifest assumes
     it already exists).
   - Decrypt and apply the ArgoCD repo-credentials secret (the GitHub
     deploy key) into that namespace, so it's in place before ArgoCD needs it.
   - Install ArgoCD (`infrastructure/argocd`) directly, since ArgoCD can't
     manage itself before it exists.
   - Wait for the repo-server to come up, confirming it can actually use
     the credential to reach the private repo.
   - Apply `root-app.yaml`, handing control to ArgoCD, which will sync
     everything else — including re-adopting its own install.

## Rotating keys

`task secrets:rotate-deploy-key` generates a new GitHub deploy key,
registers it read-only, re-encrypts the secret, and revokes the old key.
`task secrets:rotate-age-key` rotates the age keypair used to encrypt
everything under `bootstrap/secrets/`. Both scripts (under `scripts/`)
never print private key material to output. After rotating the age key,
update your external backup with the new
`~/.config/sops/age/keys.txt`.
