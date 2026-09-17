#!/usr/bin/env bash
# Creates the checkpoint storage account/container, enables the Blob CSI driver + Workload
# Identity on the cluster, and grants the AKS *kubelet* managed identity (the node identity the
# Blob CSI driver already runs as) read/write on the storage account -- the same "kubelet
# identity" mode the ServiceAccount comment in common/base/serviceaccount.yaml describes, so no
# per-pod federated credential is needed (contrast with 05-model-storage-and-data/aks, which uses
# a separate user-assigned identity + Workload Identity for that chapter's read-only model mount).
# Then writes storage/storage.env so the kustomize overlay picks up the account/container names.
set -euo pipefail
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AZ_LOCATION:?}" "${AKS_CLUSTER:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ACCOUNT="${AZ_STORAGE_ACCOUNT:-ch07ckpt$(openssl rand -hex 4)}"   # 3-24 chars, lowercase+digits, globally unique
CONTAINER="${AZ_CONTAINER:-checkpoints}"

az aks update -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}" --enable-blob-driver

if ! az storage account show -n "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" >/dev/null 2>&1; then
  az storage account create -n "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" -l "${AZ_LOCATION}" \
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false
fi
az storage container-rm create --storage-account "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" -n "${CONTAINER}" >/dev/null

# Blob CSI, when the PV gives it no secretRef and storeAccountKey isn't set, falls back to the
# node's (kubelet) managed identity to read the account key at mount time -- grant that identity
# "Storage Account Contributor" (same role ch05 grants its per-pod identity) on this account.
KUBELET_OBJECT_ID="$(az aks show -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}" \
  --query identityProfile.kubeletidentity.objectId -o tsv)"
ACCOUNT_SCOPE="$(az storage account show -n "${ACCOUNT}" -g "${AZ_RESOURCE_GROUP}" --query id -o tsv)"
az role assignment create --assignee-object-id "${KUBELET_OBJECT_ID}" --assignee-principal-type ServicePrincipal \
  --role "Storage Account Contributor" --scope "${ACCOUNT_SCOPE}" >/dev/null

cat > "${HERE}/storage/storage.env" <<ENV
# written by setup-storage.sh
AZ_STORAGE_RG=${AZ_RESOURCE_GROUP}
AZ_STORAGE_ACCOUNT=${ACCOUNT}
AZ_CONTAINER=${CONTAINER}
ENV
echo "storage account ${ACCOUNT}/${CONTAINER} ready; ${HERE}/storage/storage.env updated"
