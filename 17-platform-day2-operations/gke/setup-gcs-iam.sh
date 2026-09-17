#!/usr/bin/env bash
# Creates the Velero backup bucket and grants it to the "velero" KSA via Workload Identity
# Federation for GKE (same pattern as 05-model-storage-and-data/gke/setup-gcs-iam.sh -- no GSA
# key file, no long-lived credential to leak).
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${REGION:?}"

HERE="$(cd "$(dirname "$0")" && pwd)"
NS=velero
BUCKET="${VELERO_GCS_BUCKET:-${PROJECT_ID}-ch17-velero}"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
PRINCIPAL="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/${NS}/sa/velero"

if ! gcloud storage buckets describe "gs://${BUCKET}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${BUCKET}" \
    --project "${PROJECT_ID}" \
    --location "${REGION}" \
    --uniform-bucket-level-access
fi

# roles/storage.objectAdmin: Velero needs to list, write (backup) and delete (TTL expiry, backup
# deletion) objects in this bucket -- narrower objectCreator/objectViewer isn't enough.
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member "${PRINCIPAL}" \
  --role roles/storage.objectAdmin

printf '# written by setup-gcs-iam.sh\nVELERO_GCS_BUCKET=%s\n' "${BUCKET}" > "${HERE}/bucket.env"
echo "bucket gs://${BUCKET} ready for Velero; ${HERE}/bucket.env updated"
echo "Namespace 'velero' and its 'velero' KSA are created by install-velero.sh (Helm chart) --"
echo "run that next; the Workload Identity binding above is already in place for it."
