#!/usr/bin/env bash
# Default: remove chapter workloads and scale the GPU pool to 0. DELETE_CLUSTER=true deletes the RG.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?}" "${AKS_CLUSTER:?}"

kubectl delete -k "$HERE" --ignore-not-found || true
# With the autoscaler enabled you cannot "scale"; lower min to 0 and let it drain, or update counts.
az aks nodepool update -g "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" -n gpuspot \
  --update-cluster-autoscaler --min-count 0 --max-count 1 || true

if [[ "${DELETE_CLUSTER:-false}" == "true" ]]; then
  az group delete --name "$AZ_RESOURCE_GROUP" --yes --no-wait
  echo "Deleting ${AZ_RESOURCE_GROUP} (the MC_* node resource group is removed with the cluster)."
fi
