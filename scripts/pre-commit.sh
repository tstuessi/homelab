#!/usr/bin/env bash
# Blocks commits that would leak plaintext key material.
set -euo pipefail

if ! command -v yamlfmt >/dev/null 2>&1; then
  echo "error: yamlfmt is not installed (required to check YAML formatting)." >&2
  echo "       see bootstrap/README.md for install instructions." >&2
  exit 1
fi

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
    *.yaml|*.yml)
      if ! yamlfmt -lint -q "$f"; then
        echo "error: $f is not formatted per .yamlfmt (2-space indent)." >&2
        echo "       run: yamlfmt $f" >&2
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
