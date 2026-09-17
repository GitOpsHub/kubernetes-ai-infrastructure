#!/usr/bin/env bash
set -euo pipefail
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AKS_CLUSTER:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/bucket.env"

kubectl delete -k "${HERE}/shared-fs" --ignore-not-found || true
kubectl delete -k "${HERE}" --ignore-not-found || true

az identity delete -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}-ch05-models" || true
if [[ "${DELETE_BUCKET:-false}" == "true" ]]; then
  az storage account delete -n "${AZ_STORAGE_ACCOUNT}" -g "${AZ_STORAGE_RG}" --yes
fi
for np in ch05spot ch05od; do
  az aks nodepool delete -g "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" -n "${np}" --no-wait || true
done
