#!/usr/bin/env bash
# Azure Workload Identity (federated identity credential), same pattern as GKE/EKS. Requires
# the AKS cluster to have `--enable-oidc-issuer --enable-workload-identity` (chapter 00).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?set in env.sh}"
: "${AKS_CLUSTER:?set in env.sh}"

cat <<MSG
# Run these yourself (this script does not call az with mutating verbs):
OIDC_ISSUER=\$(az aks show -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}" --query "oidcIssuerProfile.issuerUrl" -o tsv)

az identity create -g "${AZ_RESOURCE_GROUP}" -n ch14-eso-keyvault

az role assignment create \\
  --role "Key Vault Secrets User" \\
  --assignee-object-id "\$(az identity show -g ${AZ_RESOURCE_GROUP} -n ch14-eso-keyvault --query principalId -o tsv)" \\
  --assignee-principal-type ServicePrincipal \\
  --scope "/subscriptions/${AZ_SUBSCRIPTION_ID}/resourceGroups/${AZ_RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/<your-keyvault-name>"

az identity federated-credential create \\
  --name ch14-eso-fic \\
  --identity-name ch14-eso-keyvault \\
  --resource-group "${AZ_RESOURCE_GROUP}" \\
  --issuer "\${OIDC_ISSUER}" \\
  --subject "system:serviceaccount:external-secrets:external-secrets" \\
  --audience api://AzureADTokenExchange
MSG
