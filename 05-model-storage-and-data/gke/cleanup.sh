#!/usr/bin/env bash
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${REGION:?}" "${GKE_CLUSTER:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/bucket.env"

kubectl delete -k "${HERE}/shared-fs" --ignore-not-found || true
kubectl delete -k "${HERE}" --ignore-not-found || true

if [[ "${DELETE_BUCKET:-false}" == "true" ]]; then
  gcloud storage rm --recursive "gs://${GCS_BUCKET}"
fi

gcloud container node-pools delete ch05-cpu-spot --cluster "${GKE_CLUSTER}" \
  --location "${REGION}" --project "${PROJECT_ID}" --quiet || true
gcloud container node-pools delete ch05-preloaded-spot --cluster "${GKE_CLUSTER}" \
  --location "${REGION}" --project "${PROJECT_ID}" --quiet || true
echo "Filestore instances are deleted with their PVC (reclaimPolicy Delete) – verify: gcloud filestore instances list"
