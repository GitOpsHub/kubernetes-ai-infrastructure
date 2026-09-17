#!/usr/bin/env bash
# GKE-native NVIDIA MPS sharing (Standard clusters). Pods MUST set hostIPC: true.
set -euo pipefail
source "$(dirname "$0")/_common.sh"

POOL="${POOL:-l4-mps-spot}"

gcloud container node-pools create "${POOL}" \
  --project="${PROJECT_ID}" \
  --cluster="${GKE_CLUSTER}" \
  --location="${LOCATION}" \
  --node-locations="${NODE_ZONE}" \
  --machine-type=g2-standard-4 \
  --accelerator="type=nvidia-l4,count=1,gpu-sharing-strategy=mps,max-shared-clients-per-gpu=4,gpu-driver-version=latest" \
  --spot \
  --num-nodes=0 \
  --enable-autoscaling --min-nodes=0 --max-nodes=1 \
  --node-labels=course-chapter=03

# ON-DEMAND FALLBACK: drop --spot.
