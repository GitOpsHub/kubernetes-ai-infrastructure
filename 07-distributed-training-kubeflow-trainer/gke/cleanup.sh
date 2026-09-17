#!/usr/bin/env bash
# Deletes the lab workloads and the GPU pool. Keeps the bucket unless DELETE_BUCKET=true.
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${GKE_CLUSTER:?}" "${ZONE:?}"
LOCATION="${GKE_LOCATION:-${ZONE}}"
HERE="$(cd "$(dirname "$0")" && pwd)"

kubectl delete trainjobs --all -n ch07-training --ignore-not-found
kubectl delete -k "${HERE}" --ignore-not-found || true
for pool in gpu-spot-l4 gpu-ondemand-l4; do
  gcloud container node-pools delete "${pool}" --cluster "${GKE_CLUSTER}" --location "${LOCATION}" --quiet 2>/dev/null || true
done
if [[ "${UNINSTALL_TRAINER:-false}" == "true" ]]; then
  helm uninstall kubeflow-trainer -n kubeflow-system || true
fi
if [[ "${DELETE_BUCKET:-false}" == "true" ]]; then
  gcloud storage rm --recursive "gs://${BUCKET:-${PROJECT_ID}-ch07-checkpoints}"
fi
