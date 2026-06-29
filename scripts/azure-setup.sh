#!/usr/bin/env bash
#
# Bootstrap OIDC, a lancer UNE SEULE FOIS en local (az login), par un Owner.
#
# C'est le SEUL morceau qui ne peut pas venir de la CI : pour que la CI se
# connecte a Azure sans secret (OIDC), il faut qu'une identite + une confiance
# federee existent DEJA. Or les creer demande d'etre deja authentifie => oeuf
# et poule. Tout le reste (ACR, image, environment + Container App) est cree par
# la CI elle-meme une fois connectee via cette identite (voir .gitlab-ci.yml).
#
# Ce script cree donc le minimum : resource group, providers, managed identity,
# federated credential (GitLab main -> Azure) et les roles au scope du RG.
# Aucun secret : la CI s'authentifie en OIDC.

set -euo pipefail

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

# Cible explicitement le bon abonnement (independant de l'abo actif du CLI).
select_subscription() {
  az account set --subscription "$SUBSCRIPTION"
}

# Cree le resource group : il porte le role (scope RG) et accueillera l'infra CI.
create_rg() {
  az group create -n "$RG" -l "$LOC"
}

# Enregistre les resource providers (abonnement neuf : aucun actif par defaut).
# Fait ici car ca demande un droit niveau abonnement que la CI (scope RG) n'a pas.
register_providers() {
  local ns
  for ns in Microsoft.ContainerRegistry Microsoft.App Microsoft.OperationalInsights; do
    az provider register -n "$ns" --wait
  done
}

# Identite que la CI incarnera via OIDC.
create_identity() {
  az identity create -g "$RG" -n "$MI"
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

# Roles de l'identite, au scope du RG (moindre privilege) :
# - Contributor : creer/gerer ACR + Container App depuis la CI
# - AcrPush     : pousser l'image depuis la CI (data-plane registry)
# - AcrPull     : laisser l'app ACA tirer l'image avec son identite
# Les roles ACR sont au scope RG donc valent pour l'ACR que la CI creera dedans.
assign_roles() {
  local principal scope
  principal=$(az identity show -g "$RG" -n "$MI" --query principalId -o tsv)
  scope="/subscriptions/$SUBSCRIPTION/resourceGroups/$RG"
  az role assignment create --assignee "$principal" --role Contributor --scope "$scope"
  az role assignment create --assignee "$principal" --role AcrPush --scope "$scope"
  az role assignment create --assignee "$principal" --role AcrPull --scope "$scope"
}

# Identifiants a reporter dans le bloc variables du .gitlab-ci.yml (pas des secrets).
print_ci_vars() {
  cat <<EOF

==========================================================
 [Azure Bootstrap] Identifiants pour .gitlab-ci.yml :
==========================================================
AZURE_CLIENT_ID       = $(az identity show -g "$RG" -n "$MI" --query clientId -o tsv)
AZURE_TENANT_ID       = $(az account show --query tenantId -o tsv)
AZURE_SUBSCRIPTION_ID = $(az account show --query id -o tsv)
RESOURCE_GROUP        = $RG
ACR_NAME              = $ACR
ACA_NAME              = $APP
ACA_ENV               = $ENVNAME
LOCATION              = $LOC
EOF
}

main() {
  select_subscription
  create_rg
  register_providers
  create_identity
  setup_oidc
  assign_roles
  print_ci_vars
}

main "$@"
