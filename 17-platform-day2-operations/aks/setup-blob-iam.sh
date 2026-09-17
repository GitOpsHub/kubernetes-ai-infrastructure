#!/usr/bin/env bash
# Storage account + container for Velero backups, a user-assigned managed identity, RBAC, and a
# federated credential for the "velero" ServiceAccount -- Azure Workload Identity, same pattern as
# 05-model-storage-and-data/aks/setup-blob-iam.sh. Assumes the cluster already has
# --enable-oidc-issuer --enable-workload-identity (05's create-nodepool.sh already turned these on;
# if this is a fresh cluster that skipped chapter 05, run that az aks update first).
set -euo pipefail
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AZ_LOCATION:?}" "${AKS_CLUSTER:?}"

HERE="$(cd "$(dirname "$0")" && pwd)"
NS=velero
SA=velero
ACCOUNT="${AZ_VELERO_STORAGE_ACCOUNT:-ch17velero$(openssl rand -hex 4)}"
CONTAINER=velero
UAMI="${AKS_CLUSTER}-ch17-velero"

if ! az storage account show -n "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" >/dev/null 2>&1; then
  az storage account create -n "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" -l "${AZ_LOCATION}" \
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false
fi
az storage container-rm create --storage-account "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" -n "${CONTAINER}" >/dev/null

az identity show -g "${AZ_RESOURCE_GROUP}" -n "${UAMI}" >/dev/null 2>&1 || \
  az identity create -g "${AZ_RESOURCE_GROUP}" -n "${UAMI}" -l "${AZ_LOCATION}"
CLIENT_ID="$(az identity show -g "${AZ_RESOURCE_GROUP}" -n "${UAMI}" --query clientId -o tsv)"
PRINCIPAL_ID="$(az identity show -g "${AZ_RESOURCE_GROUP}" -n "${UAMI}" --query principalId -o tsv)"
SUBSCRIPTION_ID="${AZ_SUBSCRIPTION_ID:?source env.sh}"
ACCOUNT_SCOPE="$(az storage account show -n "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" --query id -o tsv)"

# velero-plugin-for-microsoft-azure's own object storage plugin needs data-plane blob access
# (least privilege: Storage Blob Data Contributor, not the account-key-fetching "Storage Account
# Contributor" role chapter 05's Blob CSI driver needs for a different reason).
az role assignment create --assignee-object-id "${PRINCIPAL_ID}" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "${ACCOUNT_SCOPE}" >/dev/null
# Disk snapshots (volumeSnapshotLocation) need Disk Snapshot Contributor at the resource-group scope.
az role assignment create --assignee-object-id "${PRINCIPAL_ID}" --assignee-principal-type ServicePrincipal \
  --role "Disk Snapshot Contributor" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${AZ_RESOURCE_GROUP}" >/dev/null

ISSUER="$(az aks show -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}" --query oidcIssuerProfile.issuerUrl -o tsv)"
az identity federated-credential show -g "${AZ_RESOURCE_GROUP}" --identity-name "${UAMI}" -n "ch17-velero" >/dev/null 2>&1 || \
az identity federated-credential create -g "${AZ_RESOURCE_GROUP}" --identity-name "${UAMI}" \
  -n "ch17-velero" --issuer "${ISSUER}" \
  --subject "system:serviceaccount:${NS}:${SA}" --audiences api://AzureADTokenExchange

cat > "${HERE}/bucket.env" <<ENV
# written by setup-blob-iam.sh
AZ_VELERO_RESOURCE_GROUP=${AZ_RESOURCE_GROUP}
AZ_VELERO_STORAGE_ACCOUNT=${ACCOUNT}
AZ_VELERO_CONTAINER=${CONTAINER}
AZ_VELERO_MI_CLIENT_ID=${CLIENT_ID}
AZ_VELERO_SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
ENV
echo "storage account ${ACCOUNT}/${CONTAINER} ready for Velero; ${HERE}/bucket.env updated"
echo "Federated credential for ns=${NS} sa=${SA} is in place. install-velero.sh (Helm) creates"
echo "that ServiceAccount with the workload-identity client-id annotation -- run that next."
