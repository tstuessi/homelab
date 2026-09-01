#!/usr/bin/env bash
# Rotates the age keypair used to encrypt secrets under bootstrap/secrets/.
# Re-wraps all secrets for a new recipient, verifies the new key alone can
# decrypt them, then replaces the local master key file. Never prints
# private key material - only public keys, which are not secret.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
SOPS_YAML=".sops.yaml"
shopt -s nullglob
SECRETS=(bootstrap/secrets/*.yaml)
shopt -u nullglob

if [[ ! -f "$AGE_KEY_FILE" ]]; then
  echo "error: no existing age key file at $AGE_KEY_FILE" >&2
  exit 1
fi
if [[ ${#SECRETS[@]} -eq 0 ]]; then
  echo "error: no secrets found under bootstrap/secrets/" >&2
  exit 1
fi

tmpdir=$(mktemp -d)
cleanup() { shred -u "$tmpdir"/new_key.txt 2>/dev/null || true; rm -rf "$tmpdir"; }
trap cleanup EXIT

old_pub=$(grep -m1 '^# public key:' "$AGE_KEY_FILE" | awk '{print $NF}')

echo "Generating new age keypair..."
age-keygen -o "$tmpdir/new_key.txt" 2>/dev/null
new_pub=$(grep -m1 '^# public key:' "$tmpdir/new_key.txt" | awk '{print $NF}')
echo "New public key: $new_pub"

echo "Adding new recipient to $AGE_KEY_FILE (old key kept until rotation verifies)..."
cp "$AGE_KEY_FILE" "$AGE_KEY_FILE.bak"
cat "$tmpdir/new_key.txt" >> "$AGE_KEY_FILE"

echo "Updating $SOPS_YAML to the new recipient..."
sed -i "s/age: ${old_pub}/age: ${new_pub}/" "$SOPS_YAML"

echo "Re-wrapping secrets for the new recipient..."
for f in "${SECRETS[@]}"; do
  sops updatekeys -y "$f"
done

echo "Verifying the new key alone can decrypt (without the old key)..."
if ! SOPS_AGE_KEY_FILE="$tmpdir/new_key.txt" sops decrypt "${SECRETS[0]}" >/dev/null; then
  echo "error: verification failed, restoring old key file and .sops.yaml" >&2
  mv "$AGE_KEY_FILE.bak" "$AGE_KEY_FILE"
  sed -i "s/age: ${new_pub}/age: ${old_pub}/" "$SOPS_YAML"
  exit 1
fi

echo "Verification passed. Replacing local master key with the new one only..."
mv "$tmpdir/new_key.txt" "$AGE_KEY_FILE"
chmod 600 "$AGE_KEY_FILE"
shred -u "$AGE_KEY_FILE.bak" 2>/dev/null || rm -f "$AGE_KEY_FILE.bak"

echo "Done. Old age key removed from all secrets and deleted locally."
echo "IMPORTANT: update your password manager backup - run 'cat $AGE_KEY_FILE' yourself to get the new value, it was not printed here."
