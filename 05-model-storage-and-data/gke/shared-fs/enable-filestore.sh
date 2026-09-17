#!/usr/bin/env bash
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${REGION:?}" "${GKE_CLUSTER:?}"
gcloud container clusters update "${GKE_CLUSTER}" \
  --project "${PROJECT_ID}" --location "${REGION}" \
  --update-addons=GcpFilestoreCsiDriver=ENABLED
kubectl get storageclass standard-rwx premium-rwx
