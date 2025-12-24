#!/usr/bin/env bash
set -euo pipefail

# Remove generated .secret.yaml files
# Usage: ./secrets_clean.sh [FILE]

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
  files+=("$TARGET")
else
  while IFS= read -r file; do
    files+=("$file")
  done < <(find . -type f -name "*.secret.yaml" | sort)
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "No .secret.yaml files to remove."
  exit 0
fi

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    echo "Removing $file"
    rm -f "$file"
  fi
done
