#!/usr/bin/env bash
# Remove chapter workloads and let GPU pools scale to 0. DELETE_POOL=true deletes the pool.
# UNINSTALL_PLUGIN=true removes the device plugin (before chapter 02's operator).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?}" "${AKS_CLUSTER:?}"
POOL="${POOL:-gpuspot}"
kubectl delete -k "$HERE" --ignore-not-found || true
az aks nodepool update -g "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" -n "$POOL" \
  --update-cluster-autoscaler --min-count 0 --max-count 1 || true
[[ "${UNINSTALL_PLUGIN:-false}" == "true" ]] && { helm -n nvidia-device-plugin uninstall nvdp || true; }
if [[ "${DELETE_POOL:-false}" == "true" ]]; then
  az aks nodepool delete -g "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" -n "$POOL"
fi
