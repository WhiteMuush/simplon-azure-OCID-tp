#!/usr/bin/env bash
#
# Vide le resource group de TOUTES ses ressources (garde le RG lui-meme).
# Ordre important : les Container Apps avant leur environment, sinon la suppression
# de l'environment echoue tant qu'une app y vit encore.

set -euo pipefail

# Configuration externalisee, partagee avec azure-setup.sh (cf scripts/.env).
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "Erreur : $SCRIPT_DIR/.env introuvable." >&2
  exit 1
fi
set -a
# shellcheck source=/dev/null
. "$SCRIPT_DIR/.env"
set +a

az account set --subscription "$SUBSCRIPTION"

# Supprime les Container Apps (bloquent la suppression de l'environment).
delete_container_apps() {
  local apps
  apps=$(az containerapp list -g "$RG" --query "[].name" -o tsv)
  for app in $apps; do
    echo "-> container app: $app"
    az containerapp delete -g "$RG" -n "$app" --yes
  done
}

# Supprime les environments Container Apps.
delete_environments() {
  local envs
  envs=$(az containerapp env list -g "$RG" --query "[].name" -o tsv)
  for env in $envs; do
    echo "-> environment: $env"
    az containerapp env delete -g "$RG" -n "$env" --yes
  done
}

# Supprime tout le reste (ACR, managed identity, log analytics, etc.) par id.
delete_remaining() {
  local ids
  ids=$(az resource list -g "$RG" --query "[].id" -o tsv)
  if [ -n "$ids" ]; then
    echo "-> ressources restantes :"
    echo "$ids"
    az resource delete --ids $ids
  fi
}

main() {
  delete_container_apps
  delete_environments
  delete_remaining
  echo "=== contenu final du RG (vide attendu) ==="
  az resource list -g "$RG" --query "[].name" -o tsv
}

main "$@"
