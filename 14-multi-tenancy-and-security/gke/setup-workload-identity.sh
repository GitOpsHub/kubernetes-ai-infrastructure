#!/usr/bin/env bash
# Workload Identity binding so the ESO controller pod can read Secret Manager without a
# downloaded JSON key. Read-only lookups only below (no cluster mutation, no creation of
# resources) EXCEPT the two IAM bind steps, which this course's brief explicitly forbids
# running against a live account — run these two lines yourself after reviewing them.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${PROJECT_ID:?set in env.sh}"

GSA="eso-secretmanager@${PROJECT_ID}.iam.gserviceaccount.com"

cat <<MSG
# Run these yourself (this script does not call gcloud with mutating verbs):
gcloud iam service-accounts create eso-secretmanager --project "${PROJECT_ID}" \\
  --display-name "External Secrets Operator -> Secret Manager"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \\
  --member "serviceAccount:${GSA}" \\
  --role roles/secretmanager.secretAccessor

# Workload Identity: let the Kubernetes SA external-secrets/external-secrets impersonate it
gcloud iam service-accounts add-iam-policy-binding "${GSA}" \\
  --role roles/iam.workloadIdentityUser \\
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[external-secrets/external-secrets]"
MSG
