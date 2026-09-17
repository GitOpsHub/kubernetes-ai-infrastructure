#!/usr/bin/env bash
# Spot L4 GPU node pool for the Ray worker group only. The RayCluster head, the RayJob's
# ephemeral cluster and the RayService both run on your existing on-demand default node pool
# (from 00-prerequisites-and-cluster-setup) -- only GPU Ray workers need this pool.
# Requires GPU quota for NVIDIA_L4_GPUS (spot: PREEMPTIBLE_NVIDIA_L4_GPUS) in ${REGION}.
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${GKE_CLUSTER:?}" "${ZONE:?}"
LOCATION="${GKE_LOCATION:-${ZONE}}"
POOL="${POOL:-ch08-gpu-spot-l4}"
CAPACITY="${CAPACITY:-spot}"             # CAPACITY=on-demand for the fallback pool

capacity_flag=(--spot)
if [[ "${CAPACITY}" == "on-demand" ]]; then capacity_flag=(); POOL="${POOL/spot/ondemand}"; fi

gcloud container node-pools create "${POOL}" \
  --project "${PROJECT_ID}" --cluster "${GKE_CLUSTER}" --location "${LOCATION}" \
  --node-locations "${ZONE}" \
  --machine-type g2-standard-4 \
  --accelerator "type=nvidia-l4,count=1,gpu-driver-version=latest" \
  "${capacity_flag[@]}" \
  --num-nodes 0 --enable-autoscaling --min-nodes 0 --max-nodes 2 \
  --node-labels "ch08.lab/pool=${POOL}"
