#!/usr/bin/env bash
# Two CPU node pools for the chapter-06 Kueue labs: a Spot pool (default target for batch work,
# matches the "spot" ResourceFlavor) and a small on-demand pool (matches "on-demand", and is
# where install-kueue.sh pins the Kueue controller itself).
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${REGION:?}" "${GKE_CLUSTER:?}"

gcloud container node-pools create ch06-cpu-spot \
  --project "${PROJECT_ID}" \
  --cluster "${GKE_CLUSTER}" \
  --location "${REGION}" \
  --machine-type e2-standard-4 \
  --spot \
  --num-nodes 1 \
  --enable-autoscaling --min-nodes 0 --max-nodes 3 \
  --disk-type pd-balanced --disk-size 50

gcloud container node-pools create ch06-cpu-ondemand \
  --project "${PROJECT_ID}" \
  --cluster "${GKE_CLUSTER}" \
  --location "${REGION}" \
  --machine-type e2-standard-4 \
  --num-nodes 1 \
  --enable-autoscaling --min-nodes 0 --max-nodes 1 \
  --disk-type pd-balanced --disk-size 50

gcloud container node-pools list --project "${PROJECT_ID}" --cluster "${GKE_CLUSTER}" --location "${REGION}"
