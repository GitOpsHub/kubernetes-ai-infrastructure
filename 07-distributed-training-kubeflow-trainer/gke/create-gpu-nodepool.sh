#!/usr/bin/env bash
# Spot L4 GPU node pool that scales from zero. 2 nodes x 1 L4 for the 2-node DDP lab.
# Requires GPU quota for NVIDIA_L4_GPUS (spot: PREEMPTIBLE_NVIDIA_L4_GPUS) in ${REGION}.
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${GKE_CLUSTER:?}" "${ZONE:?}"
LOCATION="${GKE_LOCATION:-${ZONE}}"     # set GKE_LOCATION=${REGION} for a regional cluster
POOL="${POOL:-gpu-spot-l4}"
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
  --enable-gvnic \
  --workload-metadata GKE_METADATA \
  --node-labels "ch07.lab/pool=${POOL}"

# Advanced (not needed for this lab): multi-NIC A3/A4 pools with GPUDirect-TCPX/TCPXO/RDMA
# and compact placement -- see README "High-speed networking".
