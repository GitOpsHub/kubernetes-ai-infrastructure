#!/usr/bin/env bash
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${REGION:?}" "${GKE_CLUSTER:?}"

kubectl delete -k 06-batch-jobs-and-kueue/gke --ignore-not-found
kubectl delete -f 06-batch-jobs-and-kueue/common/jobs --ignore-not-found
helm uninstall kueue -n kueue-system || true
kubectl delete namespace kueue-system --ignore-not-found

gcloud container node-pools delete ch06-cpu-spot \
  --project "${PROJECT_ID}" --cluster "${GKE_CLUSTER}" --location "${REGION}" --quiet || true
gcloud container node-pools delete ch06-cpu-ondemand \
  --project "${PROJECT_ID}" --cluster "${GKE_CLUSTER}" --location "${REGION}" --quiet || true
