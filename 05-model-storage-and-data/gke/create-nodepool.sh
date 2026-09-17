#!/usr/bin/env bash
# Spot CPU node pool for the chapter-05 labs (vLLM CPU backend wants AVX-512 → n2 / c3 Intel families).
# Requires Workload Identity Federation on the cluster (chapter 00 creates the cluster with --workload-pool).
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${REGION:?}" "${GKE_CLUSTER:?}"

POOL="${POOL:-ch05-cpu-spot}"

# Spot first. On-demand fallback: re-run with SPOT=false (drops --spot) if spot capacity is exhausted.
SPOT_FLAG="--spot"
[[ "${SPOT:-true}" == "false" ]] && SPOT_FLAG=""

gcloud container node-pools create "${POOL}" \
  --project "${PROJECT_ID}" \
  --cluster "${GKE_CLUSTER}" \
  --location "${REGION}" \
  --machine-type n2-standard-8 \
  ${SPOT_FLAG} \
  --num-nodes 1 \
  --enable-autoscaling --min-nodes 0 --max-nodes 2 \
  --disk-type pd-balanced --disk-size 100 \
  --workload-metadata GKE_METADATA

# Cloud Storage FUSE CSI driver add-on (on by default on Autopilot; opt-in on Standard).
gcloud container clusters update "${GKE_CLUSTER}" \
  --project "${PROJECT_ID}" --location "${REGION}" \
  --update-addons GcsFuseCsiDriver=ENABLED

gcloud container clusters describe "${GKE_CLUSTER}" \
  --project "${PROJECT_ID}" --location "${REGION}" \
  --format "value(addonsConfig.gcsFuseCsiDriverConfig.enabled)"
