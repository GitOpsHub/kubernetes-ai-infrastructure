#!/usr/bin/env bash
# Create a GKE GPU node pool (spot by default) with GKE-managed NVIDIA driver + device plugin.
#   GPU_TYPE=nvidia-l4 (g2-standard-4, default) | nvidia-tesla-t4 (n1-standard-4)
#   ON_DEMAND=true      -> on-demand fallback pool (no --spot)
#   GPU_DRIVER_VERSION  -> latest (default) | default | disabled (use 'disabled' only with the GPU Operator, chapter 02)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${ZONE:?}" "${GKE_CLUSTER:?}" "${PROJECT_ID:?}"

GPU_TYPE="${GPU_TYPE:-nvidia-l4}"
case "$GPU_TYPE" in
  nvidia-l4)       DEFAULT_MACHINE=g2-standard-4 ;;
  nvidia-tesla-t4) DEFAULT_MACHINE=n1-standard-4 ;;
  *)               DEFAULT_MACHINE="${MACHINE:?set MACHINE for $GPU_TYPE}" ;;
esac
MACHINE="${MACHINE:-$DEFAULT_MACHINE}"
GPU_DRIVER_VERSION="${GPU_DRIVER_VERSION:-latest}"
MAX_NODES="${MAX_NODES:-1}"

if [[ "${ON_DEMAND:-false}" == "true" ]]; then
  POOL="${POOL:-ondemand-gpu}"; CAPACITY_FLAGS=()
else
  POOL="${POOL:-spot-gpu}";     CAPACITY_FLAGS=(--spot)
fi

gcloud compute accelerator-types list --project "$PROJECT_ID" \
  --filter="zone:${ZONE} AND name:${GPU_TYPE}" --format="value(name)" | grep -q . \
  || { echo "ERROR: ${GPU_TYPE} not available in ${ZONE}"; exit 1; }

gcloud container node-pools create "$POOL" \
  --project "$PROJECT_ID" \
  --cluster "$GKE_CLUSTER" --location "$ZONE" \
  --machine-type "$MACHINE" \
  --accelerator "type=${GPU_TYPE},count=1,gpu-driver-version=${GPU_DRIVER_VERSION}" \
  ${CAPACITY_FLAGS[@]+"${CAPACITY_FLAGS[@]}"} \
  --num-nodes 0 \
  --enable-autoscaling --min-nodes 0 --max-nodes "$MAX_NODES" \
  --disk-type pd-balanced --disk-size 100

# GKE adds automatically: taint nvidia.com/gpu=present:NoSchedule,
# labels cloud.google.com/gke-accelerator=<type>, cloud.google.com/gke-gpu-driver-version, gke-spot.
gcloud container node-pools describe "$POOL" --cluster "$GKE_CLUSTER" --location "$ZONE" \
  --format="yaml(config.accelerators,config.spot,autoscaling)"
