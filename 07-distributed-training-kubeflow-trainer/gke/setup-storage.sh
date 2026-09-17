#!/usr/bin/env bash
# Creates the checkpoint bucket, enables the GCS FUSE CSI driver and lets the
# ch07-training/trainer KSA read/write it via Workload Identity Federation for GKE.
# Then writes storage/storage.env so the kustomize overlay picks up the bucket name.
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${GKE_CLUSTER:?}" "${REGION:?}" "${ZONE:?}"
LOCATION="${GKE_LOCATION:-${ZONE}}"
BUCKET="${BUCKET:-${PROJECT_ID}-ch07-checkpoints}"
HERE="$(cd "$(dirname "$0")" && pwd)"

gcloud container clusters update "${GKE_CLUSTER}" --location "${LOCATION}" \
  --update-addons GcsFuseCsiDriver=ENABLED

gcloud storage buckets describe "gs://${BUCKET}" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://${BUCKET}" --location "${REGION}" --uniform-bucket-level-access

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member "principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/ch07-training/sa/trainer" \
  --role roles/storage.objectUser

printf 'BUCKET_NAME=%s\n' "${BUCKET}" > "${HERE}/storage/storage.env"
echo "Wrote ${HERE}/storage/storage.env (BUCKET_NAME=${BUCKET})"
