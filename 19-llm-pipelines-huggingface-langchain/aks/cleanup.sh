#!/usr/bin/env bash
# Default: delete the chapter's Kubernetes objects. The ch19spot pool autoscales to 0 on its own.
# The storage account, managed identity, ACR and node pools are KEPT.
#   DELETE_CLOUD_RESOURCES=true ./cleanup.sh   -> also delete them (storage contents too!)
# Argo Workflows is shared with chapter 15 and is left installed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AKS_CLUSTER:?}"
# shellcheck disable=SC1091
source "${HERE}/bucket.env"
NS=ch19-pipelines
ACR_NAME="${AZ_ACR_NAME:-ch19acr$(printf '%s' "${AZ_SUBSCRIPTION_ID:-}${AKS_CLUSTER}" | shasum | cut -c1-12)}"

kubectl -n "${NS}" delete workflows.argoproj.io --all --ignore-not-found 2>/dev/null || true
kubectl delete -k "${HERE}" --ignore-not-found || true
echo "GPU capacity is 01's gpuspot pool (min 0): ../../01-gpu-nodes-and-scheduling/aks/cleanup.sh"

if [[ "${DELETE_CLOUD_RESOURCES:-false}" != "true" ]]; then
  echo "KEPT: storage account ${AZ_STORAGE_ACCOUNT}, identity ${AKS_CLUSTER}-ch19-pipelines, ACR ${ACR_NAME}, pools ch19spot/ch19od."
  echo "      Re-run with DELETE_CLOUD_RESOURCES=true to delete them (storage + ACR bill monthly)."
  exit 0
fi

echo "DELETE_CLOUD_RESOURCES=true: deleting managed identity, storage account, ACR, node pools"
az identity delete -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}-ch19-pipelines" || true
az storage account delete -n "${AZ_STORAGE_ACCOUNT}" -g "${AZ_STORAGE_RG}" --yes || true
az aks update -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}" --detach-acr "${ACR_NAME}" >/dev/null 2>&1 || true
az acr delete -n "${ACR_NAME}" -g "${AZ_RESOURCE_GROUP}" --yes || true
for np in ch19spot ch19od; do
  az aks nodepool delete -g "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" -n "${np}" --no-wait 2>/dev/null || true
done
echo "ch19 AKS cloud resources deleted. (Blob CSI / Workload Identity left enabled: chapter 05 uses them.)"
