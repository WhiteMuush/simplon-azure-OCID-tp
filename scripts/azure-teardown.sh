#!/usr/bin/env bash
#
# Empties the resource group of ALL its resources (keeps the RG itself).
# Order matters: Container Apps before their environment, otherwise deleting the
# environment fails while an app still lives in it.

set -euo pipefail

# Externalized config, shared with azure-setup.sh (see scripts/.env).
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "Error: $SCRIPT_DIR/.env not found." >&2
  exit 1
fi
# shellcheck source=/dev/null
set -a; . "$SCRIPT_DIR/.env"; set +a

az account set --subscription "$SUBSCRIPTION"

# Delete the Container Apps (they block deleting the environment).
delete_container_apps() {
  local apps
  apps=$(az containerapp list -g "$RG" --query "[].name" -o tsv)
  for app in $apps; do
    echo "-> container app: $app"
    az containerapp delete -g "$RG" -n "$app" --yes
  done
}

# Delete the Container Apps environments.
delete_environments() {
  local envs
  envs=$(az containerapp env list -g "$RG" --query "[].name" -o tsv)
  for env in $envs; do
    echo "-> environment: $env"
    az containerapp env delete -g "$RG" -n "$env" --yes
  done
}

# Delete everything else (ACR, log analytics, etc.) by id. Keeps the managed
# identity ($MI): it holds the OIDC federated trust used to re-auth this
# script, deleting it would lock the pipeline out.
delete_remaining() {
  local ids
  ids=$(az resource list -g "$RG" --query "[?type!='Microsoft.ManagedIdentity/userAssignedIdentities'].id" -o tsv)
  if [ -n "$ids" ]; then
    echo "-> remaining resources:"
    echo "$ids"
    az resource delete --ids $ids
  fi
}

main() {
  delete_container_apps
  delete_environments
  delete_remaining
  echo "=== final RG content (expected: only $MI) ==="
  az resource list -g "$RG" --query "[].name" -o tsv
}

main "$@"
