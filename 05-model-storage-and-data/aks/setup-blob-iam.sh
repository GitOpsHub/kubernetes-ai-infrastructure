#!/usr/bin/env bash
# Storage account + container, a user-assigned managed identity, RBAC, and federated credentials
# for the chapter-05 ServiceAccounts (Azure Workload Identity).
set -euo pipefail
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AZ_LOCATION:?}" "${AKS_CLUSTER:?}"

HERE="$(cd "$(dirname "$0")" && pwd)"
NS=ch05-models
# 3-24 chars, lowercase letters and digits, globally unique
ACCOUNT="${AZ_STORAGE_ACCOUNT:-ch05models$(openssl rand -hex 4)}"
CONTAINER=models
UAMI="${AKS_CLUSTER}-ch05-models"

if ! az storage account show -n "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" >/dev/null 2>&1; then
  az storage account create -n "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" -l "${AZ_LOCATION}" \
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false
fi
# control-plane (ARM) create – no data-plane role needed for the person running the script
az storage container-rm create --storage-account "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" -n "${CONTAINER}" >/dev/null

az identity show -g "${AZ_RESOURCE_GROUP}" -n "${UAMI}" >/dev/null 2>&1 || \
  az identity create -g "${AZ_RESOURCE_GROUP}" -n "${UAMI}" -l "${AZ_LOCATION}"
CLIENT_ID="$(az identity show -g "${AZ_RESOURCE_GROUP}" -n "${UAMI}" --query clientId -o tsv)"
PRINCIPAL_ID="$(az identity show -g "${AZ_RESOURCE_GROUP}" -n "${UAMI}" --query principalId -o tsv)"
ACCOUNT_SCOPE="$(az storage account show -n "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" --query id -o tsv)"

# Default Blob CSI workload-identity mode: the driver uses the identity to fetch the account key,
# so it needs "Storage Account Contributor". (Effectively full account access – see README for the
# token-based, least-privilege preview mode that uses "Storage Blob Data Reader/Contributor".)
az role assignment create --assignee-object-id "${PRINCIPAL_ID}" --assignee-principal-type ServicePrincipal \
  --role "Storage Account Contributor" --scope "${ACCOUNT_SCOPE}" >/dev/null

ISSUER="$(az aks show -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}" --query oidcIssuerProfile.issuerUrl -o tsv)"
for sa in model-writer model-reader; do
  az identity federated-credential show -g "${AZ_RESOURCE_GROUP}" --identity-name "${UAMI}" -n "ch05-${sa}" >/dev/null 2>&1 || \
  az identity federated-credential create -g "${AZ_RESOURCE_GROUP}" --identity-name "${UAMI}" \
    -n "ch05-${sa}" --issuer "${ISSUER}" \
    --subject "system:serviceaccount:${NS}:${sa}" --audiences api://AzureADTokenExchange
done

cat > "${HERE}/bucket.env" <<ENV
# written by setup-blob-iam.sh
AZ_STORAGE_RG=${AZ_RESOURCE_GROUP}
AZ_STORAGE_ACCOUNT=${ACCOUNT}
AZ_CONTAINER=${CONTAINER}
AZ_MI_CLIENT_ID=${CLIENT_ID}
ENV
echo "storage account ${ACCOUNT}/${CONTAINER} ready; ${HERE}/bucket.env updated"
