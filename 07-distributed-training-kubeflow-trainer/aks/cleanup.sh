#!/usr/bin/env bash
# Deletes the lab workloads and the GPU node pool(s). Keeps the storage account unless
# DELETE_STORAGE=true.
set -euo pipefail
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AKS_CLUSTER:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"

kubectl delete trainjobs --all -n ch07-training --ignore-not-found
kubectl delete -k "${HERE}" --ignore-not-found || true
for pool in gpuspot gpuondemand; do
  az aks nodepool delete -g "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" -n "${pool}" --no-wait 2>/dev/null || true
done
if [[ "${UNINSTALL_TRAINER:-false}" == "true" ]]; then
  helm uninstall kubeflow-trainer -n kubeflow-system || true
fi
if [[ "${DELETE_STORAGE:-false}" == "true" ]]; then
  # shellcheck disable=SC1091
  source "${HERE}/storage/storage.env"
  az storage account delete -n "${AZ_STORAGE_ACCOUNT}" -g "${AZ_STORAGE_RG}" --yes
fi
