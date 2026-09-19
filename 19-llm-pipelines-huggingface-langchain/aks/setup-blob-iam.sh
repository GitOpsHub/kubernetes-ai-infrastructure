#!/usr/bin/env bash
# Storage account + container, a user-assigned managed identity, RBAC, and federated credentials
# for the chapter-19 ServiceAccounts pipeline-runner and model-reader (Azure Workload Identity).
# Idempotent (the storage account name is reused from bucket.env on re-runs). Writes bucket.env.
#
# Caveat (same as chapter 05): in the Blob CSI driver's default workload-identity mode the driver
# uses the identity to fetch the ACCOUNT KEY, so the identity needs "Storage Account Contributor"
# and the read-only / read-write split is enforced only by the pod spec (vLLM mounts readOnly).
# The token-based mode (mountWithWorkloadIdentityToken, preview) allows real least privilege with
# separate identities holding "Storage Blob Data Reader" / "Storage Blob Data Contributor".
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AZ_LOCATION:?}" "${AKS_CLUSTER:?}"

NS=ch19-pipelines
# Reuse the account a previous run created (bucket.env), unless it's the committed placeholder.
PREV_ACCOUNT="$(sed -n 's/^AZ_STORAGE_ACCOUNT=//p' "${HERE}/bucket.env" 2>/dev/null || true)"
[[ "${PREV_ACCOUNT}" == "ailabch19pipelines" ]] && PREV_ACCOUNT=""
# 3-24 chars, lowercase letters and digits, globally unique
ACCOUNT="${AZ_STORAGE_ACCOUNT:-${PREV_ACCOUNT:-ch19pipe$(openssl rand -hex 4)}}"
CONTAINER=models
UAMI="${AKS_CLUSTER}-ch19-pipelines"

if ! az storage account show -n "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" >/dev/null 2>&1; then
  az storage account create -n "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" -l "${AZ_LOCATION}" \
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false >/dev/null
fi
# control-plane (ARM) create – no data-plane role needed for the person running the script
az storage container-rm create --storage-account "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" -n "${CONTAINER}" >/dev/null

az identity show -g "${AZ_RESOURCE_GROUP}" -n "${UAMI}" >/dev/null 2>&1 || \
  az identity create -g "${AZ_RESOURCE_GROUP}" -n "${UAMI}" -l "${AZ_LOCATION}" >/dev/null
CLIENT_ID="$(az identity show -g "${AZ_RESOURCE_GROUP}" -n "${UAMI}" --query clientId -o tsv)"
PRINCIPAL_ID="$(az identity show -g "${AZ_RESOURCE_GROUP}" -n "${UAMI}" --query principalId -o tsv)"
ACCOUNT_SCOPE="$(az storage account show -n "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" --query id -o tsv)"

az role assignment create --assignee-object-id "${PRINCIPAL_ID}" --assignee-principal-type ServicePrincipal \
  --role "Storage Account Contributor" --scope "${ACCOUNT_SCOPE}" >/dev/null

ISSUER="$(az aks show -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}" --query oidcIssuerProfile.issuerUrl -o tsv)"
for sa in pipeline-runner model-reader; do
  az identity federated-credential show -g "${AZ_RESOURCE_GROUP}" --identity-name "${UAMI}" -n "ch19-${sa}" >/dev/null 2>&1 || \
  az identity federated-credential create -g "${AZ_RESOURCE_GROUP}" --identity-name "${UAMI}" \
    -n "ch19-${sa}" --issuer "${ISSUER}" \
    --subject "system:serviceaccount:${NS}:${sa}" --audiences api://AzureADTokenExchange >/dev/null
done

cat > "${HERE}/bucket.env" <<ENV
# written by setup-blob-iam.sh
AZ_STORAGE_RG=${AZ_RESOURCE_GROUP}
AZ_STORAGE_ACCOUNT=${ACCOUNT}
AZ_CONTAINER=${CONTAINER}
AZ_MI_CLIENT_ID=${CLIENT_ID}
ENV
echo "storage account ${ACCOUNT}/${CONTAINER} ready; ${HERE}/bucket.env updated"
