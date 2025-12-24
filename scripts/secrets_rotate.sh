#!/usr/bin/env bash
set -euo pipefail

# Run sops updatekeys across .sops.yaml files
# Usage: ./secrets_rotate.sh [FILE] [SSH_KEY]

TARGET="${1:-}"
SSH_KEY="${2:-$HOME/.ssh/id_ed25519}"

if [ -n "$TARGET" ]; then
  case "$TARGET" in
    *.sops.yaml) ;;
    *.secret.yaml) TARGET="${TARGET%.secret.yaml}.sops.yaml" ;;
    *.sealed.yaml) TARGET="${TARGET%.sealed.yaml}.sops.yaml" ;;
    *.yaml) TARGET="${TARGET%.yaml}.sops.yaml" ;;
    *) TARGET="${TARGET}.sops.yaml" ;;
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
  done < <(find . -type f -name "*.sops.yaml" ! -path "./.sops.yaml" | sort)
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "No .sops.yaml files found."
  exit 0
fi

AGE_KEY=$(ssh-to-age -private-key -i "$SSH_KEY")
for file in "${files[@]}"; do
  echo "Rotating keys for $file"
  SOPS_AGE_KEY="$AGE_KEY" sops updatekeys -y "$file"
done
