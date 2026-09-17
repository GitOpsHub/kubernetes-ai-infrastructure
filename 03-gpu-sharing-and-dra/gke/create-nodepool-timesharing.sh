#!/usr/bin/env bash
# GKE-native GPU time-sharing: GKE configures the device plugin for you.
# One L4 (g2-standard-4) advertised as 4 nvidia.com/gpu slots, on Spot VMs.
set -euo pipefail
source "$(dirname "$0")/_common.sh"

POOL="${POOL:-l4-timeshare-spot}"

gcloud container node-pools create "${POOL}" \
  --project="${PROJECT_ID}" \
  --cluster="${GKE_CLUSTER}" \
  --location="${LOCATION}" \
  --node-locations="${NODE_ZONE}" \
  --machine-type=g2-standard-4 \
  --accelerator="type=nvidia-l4,count=1,gpu-sharing-strategy=time-sharing,max-shared-clients-per-gpu=4,gpu-driver-version=latest" \
  --spot \
  --num-nodes=0 \
  --enable-autoscaling --min-nodes=0 --max-nodes=1 \
  --node-labels=course-chapter=03

# ON-DEMAND FALLBACK: same command without --spot and with POOL=l4-timeshare-ondemand.
# Keep max-nodes small; on-demand L4 costs ~3x the Spot price.

echo "Node pool ${POOL} created. Nodes carry the labels:"
echo "  cloud.google.com/gke-gpu-sharing-strategy=time-sharing"
echo "  cloud.google.com/gke-max-shared-clients-per-gpu=4"
