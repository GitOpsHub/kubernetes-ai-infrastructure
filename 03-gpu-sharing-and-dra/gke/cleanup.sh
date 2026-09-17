#!/usr/bin/env bash
# Delete everything chapter 03 created on GKE. GPU node pools bill per second - run this.
set -euo pipefail
source "$(dirname "$0")/_common.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

for k in timeslicing mps mig dra; do
  kubectl delete -k "${DIR}/${k}" --ignore-not-found --wait=false || true
done
helm uninstall nvidia-dra-driver-gpu -n nvidia-dra-driver-gpu 2>/dev/null || true
kubectl delete namespace nvidia-dra-driver-gpu --ignore-not-found --wait=false

for pool in l4-timeshare-spot l4-mps-spot a100-mig-spot l4-dra-spot; do
  if gcloud container node-pools describe "${pool}" --cluster="${GKE_CLUSTER}" \
       --location="${LOCATION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud container node-pools delete "${pool}" --cluster="${GKE_CLUSTER}" \
      --location="${LOCATION}" --project="${PROJECT_ID}" --quiet
  fi
done
