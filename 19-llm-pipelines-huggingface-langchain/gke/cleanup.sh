#!/usr/bin/env bash
# Default: delete the chapter's Kubernetes objects. The ch19-cpu-spot pool autoscales to 0 on its own
# (min-nodes 0) once nothing runs there. The bucket, its IAM bindings, the Artifact Registry repo
# and the node pool are KEPT.
#   DELETE_CLOUD_RESOURCES=true ./cleanup.sh   -> also delete them (bucket contents too!)
# Argo Workflows is shared with chapter 15 and is left installed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${PROJECT_ID:?source env.sh}" "${REGION:?}" "${ZONE:?}" "${GKE_CLUSTER:?}"
# Cluster/node pool live in the zonal cluster from chapter 00; the AR repo is regional.
GKE_LOCATION="${GKE_LOCATION:-${ZONE}}"
# shellcheck disable=SC1091
source "${HERE}/bucket.env"
NS=ch19-pipelines

kubectl -n "${NS}" delete workflows.argoproj.io --all --ignore-not-found 2>/dev/null || true
kubectl delete -k "${HERE}" --ignore-not-found || true
echo "GPU capacity is 01's spot-gpu pool (min 0): ../../01-gpu-nodes-and-scheduling/gke/cleanup.sh"

if [[ "${DELETE_CLOUD_RESOURCES:-false}" != "true" ]]; then
  echo "KEPT: gs://${GCS_BUCKET}, Artifact Registry repo ${AR_REPO:-ch19}, node pool ch19-cpu-spot."
  echo "      Re-run with DELETE_CLOUD_RESOURCES=true to delete them (bucket + registry storage bill monthly)."
  exit 0
fi

echo "DELETE_CLOUD_RESOURCES=true: deleting bucket (with its IAM bindings), Artifact Registry repo, node pool"
if gcloud storage buckets describe "gs://${GCS_BUCKET}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage rm --recursive "gs://${GCS_BUCKET}" --project "${PROJECT_ID}"
fi
gcloud artifacts repositories delete "${AR_REPO:-ch19}" --location "${REGION}" --project "${PROJECT_ID}" --quiet || true
gcloud container node-pools delete ch19-cpu-spot --cluster "${GKE_CLUSTER}" \
  --location "${GKE_LOCATION}" --project "${PROJECT_ID}" --quiet || true
echo "ch19 GKE cloud resources deleted. (GcsFuseCsiDriver add-on left enabled: chapter 05 uses it.)"
