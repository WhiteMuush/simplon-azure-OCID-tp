#!/usr/bin/env bash
#
# OIDC bootstrap: run ONCE locally (az login, as an Owner).
# Creates the minimum that CANNOT come from the CI (chicken-and-egg: connecting
# via OIDC assumes the identity + federated trust already exist): resource
# group, providers, managed identity, federated credential and roles (RG scope).
# Everything else (ACR, image, environment, Container App) is created by the CI.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Config in clear (identifiers only, no secret): SUBSCRIPTION, RG, LOC,
# ACR, ENVNAME, APP, MI, GITLAB_PROJECT.
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "Error: $SCRIPT_DIR/.env not found." >&2
  exit 1
fi
# shellcheck source=/dev/null
set -a; . "$SCRIPT_DIR/.env"; set +a

# Resource group: holds the roles (RG scope) and hosts the infra created by the CI.
create_rg() {
  az group create -n "$RG" -l "$LOC"
}

# Providers: a fresh subscription has none registered. Done here because it needs
# a subscription-level right the CI (RG scope) does not have.
register_providers() {
  local ns
  for ns in Microsoft.ContainerRegistry Microsoft.App Microsoft.OperationalInsights; do
    az provider register -n "$ns" --wait
  done
}

# Managed identity the CI will impersonate via OIDC.
create_identity() {
  az identity create -g "$RG" -n "$MI"
}

# Federated trust: Azure accepts JWTs from this GitLab project, main branch.
setup_oidc() {
  az identity federated-credential create \
    --name gitlab-main \
    --identity-name "$MI" \
    --resource-group "$RG" \
    --issuer https://gitlab.com \
    --subject "project_path:$GITLAB_PROJECT:ref_type:branch:ref:main" \
    --audiences "api://AzureADTokenExchange"
}

# RG-scoped roles (least privilege, also valid for the ACR the CI creates inside):
# Contributor (manage ACR + ACA), AcrPush (CI push), AcrPull (pull by the ACA app).
assign_roles() {
  local principal scope role
  principal=$(az identity show -g "$RG" -n "$MI" --query principalId -o tsv)
  scope="/subscriptions/$SUBSCRIPTION/resourceGroups/$RG"
  for role in Contributor AcrPush AcrPull; do
    az role assignment create --assignee "$principal" --role "$role" --scope "$scope"
  done
}

# Identifiers to copy into the variables block of .gitlab-ci.yml (not secrets).
print_ci_vars() {
  cat <<EOF

==========================================================
 [Azure Bootstrap] Identifiers for .gitlab-ci.yml:
==========================================================
AZURE_CLIENT_ID       = $(az identity show -g "$RG" -n "$MI" --query clientId -o tsv)
AZURE_TENANT_ID       = $(az account show --query tenantId -o tsv)
AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION
RESOURCE_GROUP        = $RG
ACR_NAME              = $ACR
ACA_NAME              = $APP
ACA_ENV               = $ENVNAME
LOCATION              = $LOC
EOF
}

main() {
  az account set --subscription "$SUBSCRIPTION"
  create_rg
  register_providers
  create_identity
  setup_oidc
  assign_roles
  print_ci_vars
}

main "$@"
