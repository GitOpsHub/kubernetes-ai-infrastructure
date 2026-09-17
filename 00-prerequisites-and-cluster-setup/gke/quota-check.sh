#!/usr/bin/env bash
# Read-only: show GPU quotas relevant to this course. Spot GPUs use PREEMPTIBLE_NVIDIA_*_GPUS
# (regional) when that quota is > 0; otherwise they consume the on-demand NVIDIA_*_GPUS quota.
# GPUS_ALL_REGIONS (global) caps both.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${PROJECT_ID:?}" "${REGION:?}"

echo "== Regional GPU quotas in ${REGION} =="
gcloud compute regions describe "$REGION" --project "$PROJECT_ID" --format=json \
  | jq -r '.quotas[] | select(.metric | test("NVIDIA|GPU")) | "\(.metric)\tlimit=\(.limit)\tusage=\(.usage)"'

echo "== Global GPUS_ALL_REGIONS =="
gcloud compute project-info describe --project "$PROJECT_ID" --format=json \
  | jq -r '.quotas[] | select(.metric=="GPUS_ALL_REGIONS") | "\(.metric)\tlimit=\(.limit)\tusage=\(.usage)"'

cat <<MSG

To request more (Console: IAM & Admin > Quotas & System Limits, filter "Preemptible NVIDIA L4 GPUs"):
  # find the exact quota id first (read-only)
  gcloud quotas info list --service=compute.googleapis.com --project=${PROJECT_ID} \\
     --filter="quotaId~PREEMPTIBLE.*NVIDIA" --format="value(quotaId)"
  # then request, e.g. 1 spot L4 in ${REGION}   # VERIFY: quota id printed by the command above
  gcloud quotas preferences create --service=compute.googleapis.com --project=${PROJECT_ID} \\
     --quota-id=<QUOTA_ID> --preferred-value=1 --dimensions=region=${REGION} \\
     --justification="Learning GPU scheduling on GKE spot"
  # and GPUS_ALL_REGIONS >= 1 (global quota, no region dimension)
MSG
