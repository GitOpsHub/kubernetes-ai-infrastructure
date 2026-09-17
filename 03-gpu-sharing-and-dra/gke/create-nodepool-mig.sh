#!/usr/bin/env bash
# ADVANCED / EXPENSIVE: MIG needs an A100/H100-class GPU. L4 and T4 do NOT support MIG.
# a2-highgpu-1g = 1x A100 40GB, partitioned by GKE into 7x 1g.5gb slices.
# Each slice is advertised as nvidia.com/gpu: 1 (GKE uses the MIG "single" style).
# Requires A100 quota in the zone (preemptible/spot quota is separate from on-demand).
set -euo pipefail
source "$(dirname "$0")/_common.sh"

POOL="${POOL:-a100-mig-spot}"
PARTITION="${PARTITION:-1g.5gb}"   # A100 40GB: 1g.5gb | 2g.10gb | 3g.20gb | 7g.40gb

gcloud container node-pools create "${POOL}" \
  --project="${PROJECT_ID}" \
  --cluster="${GKE_CLUSTER}" \
  --location="${LOCATION}" \
  --node-locations="${NODE_ZONE}" \
  --machine-type=a2-highgpu-1g \
  --accelerator="type=nvidia-tesla-a100,count=1,gpu-partition-size=${PARTITION},gpu-driver-version=latest" \
  --spot \
  --num-nodes=0 \
  --enable-autoscaling --min-nodes=0 --max-nodes=1 \
  --node-labels=course-chapter=03

# ON-DEMAND FALLBACK: drop --spot (A100 on-demand is several $/hour - delete right after the lab).
# The partition size is immutable: to change it, create a new node pool.
