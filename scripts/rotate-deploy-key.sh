#!/usr/bin/env bash
# Rotates the GitHub deploy key used by ArgoCD: generates a new keypair,
# registers it read-only on GitHub, re-encrypts the sops secret with it,
# then revokes any previously-registered deploy key. Never prints key
# material to stdout.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

REPO="tstuessi/homelab"
SECRET_FILE="bootstrap/secrets/argocd-repo-creds.yaml"
TITLE="argocd-homelab-$(date +%Y%m%d%H%M%S)"

tmpdir=$(mktemp -d)
cleanup() { shred -u "$tmpdir"/deploy_key "$tmpdir"/deploy_key.pub "$tmpdir"/updated.yaml 2>/dev/null || true; rm -rf "$tmpdir"; }
trap cleanup EXIT

echo "Generating new deploy keypair..."
ssh-keygen -q -t ed25519 -f "$tmpdir/deploy_key" -C "$TITLE" -N ""

echo "Registering new read-only deploy key on $REPO..."
gh repo deploy-key add "$tmpdir/deploy_key.pub" --title "$TITLE" --repo "$REPO"

echo "Re-encrypting $SECRET_FILE with the new key..."
sops decrypt --output-type json "$SECRET_FILE" \
  | jq --rawfile key "$tmpdir/deploy_key" '.stringData.sshPrivateKey = $key' \
  | sops encrypt --input-type json --output-type yaml --filename-override "$SECRET_FILE" /dev/stdin \
  > "$tmpdir/updated.yaml"
mv "$tmpdir/updated.yaml" "$SECRET_FILE"

echo "Verifying the secret still decrypts..."
sops decrypt "$SECRET_FILE" >/dev/null

echo "Revoking previously-registered deploy key(s)..."
gh api "repos/$REPO/keys" --jq ".[] | select(.title != \"$TITLE\") | .id" | while read -r id; do
  gh api -X DELETE "repos/$REPO/keys/$id"
  echo "  revoked key id $id"
done

echo "Done. New deploy key '$TITLE' is live; review and commit the updated $SECRET_FILE."
