#!/usr/bin/env bash
set -euo pipefail

# Turn .secret.yaml files into .sealed.yaml manifests
# Usage: ./secrets_seal.sh [FILE] [SSH_KEY] [KUBE_CONTROLLER] [KUBE_NAMESPACE] [KUBE_CONTEXT]

TARGET="${1:-}"
SSH_KEY="${2:-$HOME/.ssh/id_ed25519}"
RAW_CONTROLLER="${3:-}"
RAW_NAMESPACE="${4:-}"
RAW_CONTEXT="${5:-}"
CONTROLLER="${RAW_CONTROLLER:-sealed-secrets}"
NAMESPACE="${RAW_NAMESPACE:-kube-system}"
CONTEXT="${RAW_CONTEXT:-}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
META_EXTRACTOR="$REPO_ROOT/scripts/sealed_controller_meta.py"
KUBE_CONFIG_BASENAME=".kube-seal.yaml"

trim_ws() {
  local str="$1"
  str="${str#${str%%[![:space:]]*}}"
  str="${str%${str##*[![:space:]]}}"
  printf '%s' "${str}"
}

strip_quotes() {
  local val="$1"
  local first="${val:0:1}"
  local last="${val: -1}"
  if [ "${#val}" -ge 2 ] && [ "$first" = "$last" ]; then
    if [ "$first" = "'" ] || [ "$first" = "\"" ]; then
      val="${val:1:${#val}-2}"
    fi
  fi
  printf '%s' "$val"
}

resolve_kube_config_path() {
  local target="$1"
  local dir
  dir="$(cd "$(dirname "$target")" && pwd -P)"

  while [ -n "$dir" ]; do
    if [ -f "$dir/$KUBE_CONFIG_BASENAME" ]; then
      printf '%s\n' "$dir/$KUBE_CONFIG_BASENAME"
      return 0
    fi
    if [ "$dir" = "$REPO_ROOT" ] || [ "$dir" = "/" ]; then
      break
    fi
    dir="$(dirname "$dir")"
  done

  if [ -f "$REPO_ROOT/$KUBE_CONFIG_BASENAME" ]; then
    printf '%s\n' "$REPO_ROOT/$KUBE_CONFIG_BASENAME"
    return 0
  fi
  return 1
}

read_kube_config_values() {
  local config_path="$1"
  local controller=""
  local namespace=""
  local context=""
  local line key value trimmed

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    trimmed="$(trim_ws "$line")"
    [ -z "$trimmed" ] && continue
    case "$trimmed" in
      *:*)
        key="$(trim_ws "${trimmed%%:*}")"
        value="$(trim_ws "${trimmed#*:}")"
        value="$(strip_quotes "$value")"
        case "$key" in
          controller|controller_name|controllerName)
            controller="$value"
            ;;
          namespace|ns)
            namespace="$value"
            ;;
          context|ctx)
            context="$value"
            ;;
        esac
        ;;
    esac
  done < "$config_path"

  printf '%s\n' "$controller"
  printf '%s\n' "$namespace"
  printf '%s\n' "$context"
}

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

for file in "${files[@]}"; do
  secret="${file%.sops.yaml}.secret.yaml"
  sealed="${file%.sops.yaml}.sealed.yaml"

  if [ ! -f "$secret" ]; then
    echo "Missing $secret, decrypting from $file"
    SOPS_AGE_KEY="$AGE_KEY" sops -d "$file" > "$secret"
  fi

  effective_controller="$CONTROLLER"
  effective_namespace="$NAMESPACE"
  effective_context="$CONTEXT"

  if { [ -z "$RAW_CONTROLLER" ] || [ -z "$RAW_NAMESPACE" ] || [ -z "$RAW_CONTEXT" ]; } \
    && kube_config_path="$(resolve_kube_config_path "$file" 2>/dev/null)"; then
    mapfile -t kube_values < <(read_kube_config_values "$kube_config_path") || kube_values=()
    if [ -z "$RAW_CONTROLLER" ] && [ -n "${kube_values[0]:-}" ]; then
      effective_controller="${kube_values[0]}"
    fi
    if [ -z "$RAW_NAMESPACE" ] && [ -n "${kube_values[1]:-}" ]; then
      effective_namespace="${kube_values[1]}"
    fi
    if [ -z "$RAW_CONTEXT" ] && [ -n "${kube_values[2]:-}" ]; then
      effective_context="${kube_values[2]}"
    fi
  fi

  controller_name_from_meta=""
  controller_namespace_from_meta=""
  if command -v python3 >/dev/null 2>&1 && [ -f "$META_EXTRACTOR" ]; then
    meta_out="$(python3 "$META_EXTRACTOR" "$secret" || true)"
    if [ -n "$meta_out" ]; then
      eval "$meta_out"
    fi
  fi

  if [ -n "${controller_name_from_meta:-}" ]; then
    effective_controller="$controller_name_from_meta"
  fi

  if [ -n "${controller_namespace_from_meta:-}" ]; then
    effective_namespace="$controller_namespace_from_meta"
  fi

  kubeseal_args=("--controller-name=$effective_controller" "--controller-namespace=$effective_namespace")
  if [ -n "$effective_context" ]; then
    kubeseal_args+=("--context=$effective_context")
  fi
  kubeseal_args+=("${common_kubeseal_args[@]}")

  echo "Sealing $secret -> $sealed (controller ns: $effective_namespace)"
  kubeseal "${kubeseal_args[@]}" < "$secret" > "$sealed"
done
