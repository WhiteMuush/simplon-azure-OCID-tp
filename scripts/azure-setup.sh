#!/usr/bin/env bash
#
# Bootstrap one-shot de l'infra Azure pour le deploiement de l'app via GitLab CI.
# A lancer UNE SEULE FOIS, sur un resource group vide.
# Cree : ACR, managed identity, image bootstrap, roles, environment + Container App,
# confiance federee OIDC (GitLab -> Azure), et affiche les variables a mettre dans GitLab.
#
# Ne contient AUCUN secret : on s'authentifie a Azure en OIDC depuis la CI.
# Prerequis : etre connecte ( az login ) et avoir le Dockerfile a la racine du repo.

set -euo pipefail

# Repertoire du script (avant de changer de dossier), pour trouver le .env.
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Configuration lue dans .env (versionne en clair : que des identifiants, pas de secret).
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "Erreur : $SCRIPT_DIR/.env introuvable." >&2
  exit 1
fi
set -a
# shellcheck source=/dev/null
. "$SCRIPT_DIR/.env"
set +a

# Se placer a la racine du repo (le script vit dans scripts/), pour le build docker.
cd "$SCRIPT_DIR/.."

# Cible explicitement le bon abonnement (independant de l'abo actif du CLI).
select_subscription() {
  az account set --subscription "$SUBSCRIPTION"
}

# Cree le resource group (le nouvel abonnement est vide).
create_rg() {
  az group create -n "$RG" -l "$LOC"
}

# Enregistre les resource providers (abonnement neuf : aucun actif par defaut).
# --wait bloque jusqu'a l'etat Registered, sinon les creations suivantes echouent.
register_providers() {
  local ns
  for ns in Microsoft.ContainerRegistry Microsoft.App Microsoft.OperationalInsights; do
    az provider register -n "$ns" --wait
  done
}

# Registre d'images prive.
create_acr() {
  az acr create -g "$RG" -n "$ACR" --sku Basic
}

# Identite que la CI incarnera via OIDC.
create_identity() {
  az identity create -g "$RG" -n "$MI"
}

# 1er build + push : l'app a besoin d'une image existante pour demarrer.
# Build local + push (ACR Tasks / `az acr build` interdit sur cet abonnement).
build_image() {
  az acr login -n "$ACR"
  docker build -t "$ACR.azurecr.io/python-app:bootstrap" .
  docker push "$ACR.azurecr.io/python-app:bootstrap"
}

# Droits de l'identite sur l'ACR : push (build CI) + pull (app).
assign_acr_roles() {
  local acr_id principal
  acr_id=$(az acr show -n "$ACR" --query id -o tsv)
  principal=$(az identity show -g "$RG" -n "$MI" --query principalId -o tsv)
  az role assignment create --assignee "$principal" --role AcrPush --scope "$acr_id"
  az role assignment create --assignee "$principal" --role AcrPull --scope "$acr_id"
}

# Environment + Container App (port 8080, identite attachee pour tirer l'image sans secret).
create_app() {
  local mi_id
  az containerapp env create -g "$RG" -n "$ENVNAME" --location "$LOC"
  mi_id=$(az identity show -g "$RG" -n "$MI" --query id -o tsv)
  az containerapp create \
    -g "$RG" -n "$APP" \
    --environment "$ENVNAME" \
    --image "$ACR.azurecr.io/python-app:bootstrap" \
    --target-port 8080 \
    --ingress external \
    --user-assigned "$mi_id" \
    --registry-server "$ACR.azurecr.io" \
    --registry-identity "$mi_id"
}

# Confiance federee OIDC : Azure fait confiance aux JWT de ce projet GitLab, branche main.
setup_oidc() {
  az identity federated-credential create \
    --name gitlab-main \
    --identity-name "$MI" \
    --resource-group "$RG" \
    --issuer https://gitlab.com \
    --subject "project_path:$GITLAB_PROJECT:ref_type:branch:ref:main" \
    --audiences "api://AzureADTokenExchange"
}

# Droit de deployer : mettre a jour l'ACA depuis la CI.
assign_deploy_role() {
  local principal sub
  principal=$(az identity show -g "$RG" -n "$MI" --query principalId -o tsv)
  sub=$(az account show --query id -o tsv)
  az role assignment create --assignee "$principal" \
    --role Contributor \
    --scope "/subscriptions/$sub/resourceGroups/$RG"
}

# Variables a coller dans GitLab (ou en clair dans .gitlab-ci.yml). Identifiants, pas des secrets.
print_gitlab_vars() {
  cat <<EOF

==========================================================
 [Azure Setup] Récapitulatif du script :
==========================================================
AZURE_CLIENT_ID       = $(az identity show -g "$RG" -n "$MI" --query clientId -o tsv)
AZURE_TENANT_ID       = $(az account show --query tenantId -o tsv)
AZURE_SUBSCRIPTION_ID = $(az account show --query id -o tsv)
ACR_NAME              = $ACR
ACA_NAME              = $APP
RESOURCE_GROUP        = $RG
ACA_FQDN              = $(az containerapp show -g "$RG" -n "$APP" --query properties.configuration.ingress.fqdn -o tsv)
EOF
}

main() {
  select_subscription
  create_rg
  register_providers
  create_acr
  create_identity
  build_image
  assign_acr_roles
  create_app
  setup_oidc
  assign_deploy_role
  print_gitlab_vars
}

main "$@"
