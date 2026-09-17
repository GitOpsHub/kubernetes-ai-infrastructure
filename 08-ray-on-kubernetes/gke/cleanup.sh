#!/usr/bin/env bash
# Deletes the lab workloads and the GPU pool.
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${GKE_CLUSTER:?}" "${ZONE:?}"
LOCATION="${GKE_LOCATION:-${ZONE}}"
HERE="$(cd "$(dirname "$0")" && pwd)"

kubectl delete rayservices,rayjobs,rayclusters --all -n ch08-ray --ignore-not-found
kubectl delete -k "${HERE}" --ignore-not-found || true
for pool in ch08-gpu-spot-l4 ch08-gpu-ondemand-l4; do
  gcloud container node-pools delete "${pool}" --cluster "${GKE_CLUSTER}" --location "${LOCATION}" --quiet 2>/dev/null || true
done
if [[ "${UNINSTALL_OPERATOR:-false}" == "true" ]]; then
  helm uninstall kuberay-operator -n kuberay-system || true
fi
