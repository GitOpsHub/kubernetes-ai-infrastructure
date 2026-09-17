#!/usr/bin/env bash
# Creates the model bucket and grants IAM directly to Kubernetes ServiceAccounts
# (Workload Identity Federation for GKE principal identifiers – no Google service account needed).
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${REGION:?}"

HERE="$(cd "$(dirname "$0")" && pwd)"
NS=ch05-models
BUCKET="${GCS_BUCKET:-${PROJECT_ID}-ch05-models}"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
PRINCIPAL_BASE="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/${NS}/sa"

# Same region as the cluster: no egress charges, lowest latency.
if ! gcloud storage buckets describe "gs://${BUCKET}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${BUCKET}" \
    --project "${PROJECT_ID}" \
    --location "${REGION}" \
    --uniform-bucket-level-access
fi

# Loader Job: read/write objects.
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member "${PRINCIPAL_BASE}/model-writer" \
  --role roles/storage.objectUser

# Serving pods: read-only.
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member "${PRINCIPAL_BASE}/model-reader" \
  --role roles/storage.objectViewer

printf '# written by setup-gcs-iam.sh\nGCS_BUCKET=%s\n' "${BUCKET}" > "${HERE}/bucket.env"
echo "bucket gs://${BUCKET} ready; ${HERE}/bucket.env updated"
