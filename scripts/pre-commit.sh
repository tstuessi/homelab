#!/usr/bin/env bash
# Blocks commits that would leak plaintext key material.
set -euo pipefail

staged=$(git diff --cached --name-only --diff-filter=ACM)
fail=0

for f in $staged; do
  case "$f" in
    bootstrap/secrets/*.yaml)
      if ! git show ":$f" | grep -q '^sops:'; then
        echo "error: $f is under bootstrap/secrets/ but is not sops-encrypted (no 'sops:' key found)." >&2
        echo "       run: sops -e -i $f" >&2
        fail=1
      fi
      ;;
  esac

  if git show ":$f" | grep -qE 'BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY'; then
    echo "error: $f appears to contain an unencrypted private key." >&2
    fail=1
  fi
done

exit $fail
