#!/usr/bin/env bash
set -euo pipefail

# Re-encrypt updated .secret.yaml files back into .sops.yaml
# Usage: ./secrets_checkin.sh [FILE]

TARGET="${1:-}"

if [ -n "$TARGET" ]; then
  case "$TARGET" in
    *.secret.yaml) ;;
    *.sops.yaml) TARGET="${TARGET%.sops.yaml}.secret.yaml" ;;
    *.sealed.yaml) TARGET="${TARGET%.sealed.yaml}.secret.yaml" ;;
    *.yaml) TARGET="${TARGET%.yaml}.secret.yaml" ;;
    *) TARGET="${TARGET}.secret.yaml" ;;
  esac
fi

files=()
if [ -n "$TARGET" ]; then
  if [ ! -f "$TARGET" ]; then
    echo "File $TARGET not found" >&2
    exit 1
  fi
  files+=("$TARGET")
else
  while IFS= read -r file; do
    files+=("$file")
  done < <(find . -type f -name "*.secret.yaml" | sort)
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "No .secret.yaml files found."
  exit 0
fi

for secret in "${files[@]}"; do
  if [ ! -f "$secret" ]; then
    echo "Skipping missing $secret"
    continue
  fi

  sops_file="${secret%.secret.yaml}.sops.yaml"
  if [ -f "$sops_file" ] && [ "$secret" -ot "$sops_file" ]; then
    echo "Skipping $secret (encrypted file newer)"
    continue
  fi

  if [ ! -s "$secret" ]; then
    echo "Skipping $secret (plaintext is empty)"
    continue
  fi

  tmp="$(mktemp "${sops_file}.XXXXXX")"
  cp "$secret" "$tmp"
  echo "Encrypting $secret -> $sops_file"
  if sops --encrypt --input-type yaml --output-type yaml --in-place "$tmp"; then
    mv "$tmp" "$sops_file"
  else
    rm -f "$tmp"
    echo "Failed to encrypt $secret" >&2
    exit 1
  fi
done
