#!/usr/bin/env bash
# Creates the chapter bucket and grants IAM directly to the Kubernetes ServiceAccounts
# (Workload Identity Federation for GKE principal identifiers -- no Google service account):
#   pipeline-runner -> roles/storage.objectUser    (Argo steps: read + write new objects)
#   model-reader    -> roles/storage.objectViewer  (vLLM: read-only)
# Idempotent. Writes bucket.env.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${PROJECT_ID:?source env.sh}" "${REGION:?}"

NS=ch19-pipelines
BUCKET="${GCS_BUCKET:-${PROJECT_ID}-ch19-pipelines}"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
PRINCIPAL_BASE="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/${NS}/sa"

# Same region as the cluster: no egress charges, lowest latency.
if ! gcloud storage buckets describe "gs://${BUCKET}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${BUCKET}" \
    --project "${PROJECT_ID}" \
    --location "${REGION}" \
    --uniform-bucket-level-access
fi

gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member "${PRINCIPAL_BASE}/pipeline-runner" \
  --role roles/storage.objectUser >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member "${PRINCIPAL_BASE}/model-reader" \
  --role roles/storage.objectViewer >/dev/null

printf '# written by setup-gcs-iam.sh\nGCS_BUCKET=%s\n' "${BUCKET}" > "${HERE}/bucket.env"
echo "bucket gs://${BUCKET} ready (pipeline-runner rw, model-reader ro); ${HERE}/bucket.env updated"
