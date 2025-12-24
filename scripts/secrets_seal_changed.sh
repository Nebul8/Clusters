#!/usr/bin/env bash
set -euo pipefail

# Seal only the secrets whose .sops.yaml has changed
# Usage: ./secrets_seal_changed.sh [FILE] [SSH_KEY] [KUBE_CONTROLLER] [KUBE_NAMESPACE] [KUBE_CONTEXT]

TARGET="${1:-}"
SSH_KEY="${2:-$HOME/.ssh/id_ed25519}"
CONTROLLER="${3:-sealed-secrets}"
NAMESPACE="${4:-kube-system}"
CONTEXT="${5:-}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
META_EXTRACTOR="$REPO_ROOT/scripts/sealed_controller_meta.py"

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
common_kubeseal_args=("--format=yaml")
if [ -n "$CONTEXT" ]; then
  common_kubeseal_args+=("--context=$CONTEXT")
fi

updated=0
for file in "${files[@]}"; do
  secret="${file%.sops.yaml}.secret.yaml"
  sealed="${file%.sops.yaml}.sealed.yaml"

  if [ ! -f "$secret" ] || [ "$file" -nt "$secret" ]; then
    echo "Refreshing plaintext $secret from $file"
    SOPS_AGE_KEY="$AGE_KEY" sops -d "$file" > "$secret"
  fi

  if [ ! -f "$sealed" ] || [ "$file" -nt "$sealed" ] || [ "$secret" -nt "$sealed" ]; then
    controller_name_from_meta=""
    controller_namespace_from_meta=""
    if command -v python3 >/dev/null 2>&1 && [ -f "$META_EXTRACTOR" ]; then
      meta_out="$(python3 "$META_EXTRACTOR" "$secret" || true)"
      if [ -n "$meta_out" ]; then
        eval "$meta_out"
      fi
    fi

    effective_controller="$CONTROLLER"
    if [ -n "${controller_name_from_meta:-}" ]; then
      effective_controller="$controller_name_from_meta"
    fi

    effective_namespace="$NAMESPACE"
    if [ -n "${controller_namespace_from_meta:-}" ]; then
      effective_namespace="$controller_namespace_from_meta"
    fi

    kubeseal_args=("--controller-name=$effective_controller" "--controller-namespace=$effective_namespace")
    kubeseal_args+=("${common_kubeseal_args[@]}")

    updated=1
    echo "Sealing $secret -> $sealed (controller ns: $effective_namespace)"
    kubeseal "${kubeseal_args[@]}" < "$secret" > "$sealed"
  else
    echo "Skipping $sealed (already up to date)"
  fi
done

if [ $updated -eq 0 ]; then
  echo "No secrets required resealing."
fi
