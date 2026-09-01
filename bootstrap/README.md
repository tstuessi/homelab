# Bootstrap / disaster recovery

Everything the cluster needs is in this repo, with one exception: the
**age private key** used to decrypt `secrets/argocd-repo-creds.yaml`. That
key is not in git on purpose — back it up somewhere durable outside this
repo (e.g. a password manager entry) before you need it.

## Rebuilding from scratch

1. Install `sops`, `age`, `kubectl`, and `task` on the machine you're
   bootstrapping from.
2. Restore the age private key to `~/.config/sops/age/keys.txt` (sops'
   default lookup location) from your backup.
3. Point `kubectl` at the new cluster.
4. Run `task bootstrap`. This will:
   - Install ArgoCD (`infrastructure/argocd`) directly, since ArgoCD can't
     manage itself before it exists.
   - Decrypt and apply the ArgoCD repo-credentials secret (the GitHub
     deploy key), so ArgoCD can clone this private repo.
   - Apply `root-app.yaml`, handing control to ArgoCD, which will sync
     everything else — including re-adopting its own install from step one.

## Rotating the deploy key

Generate a new SSH keypair, add the public half as a read-only Deploy Key
on the GitHub repo, then update and re-encrypt the secret:

```
task secrets:edit -- bootstrap/secrets/argocd-repo-creds.yaml
```

`sops` decrypts to a temp file, opens `$EDITOR`, and re-encrypts on save —
the plaintext never gets written into the repo.
