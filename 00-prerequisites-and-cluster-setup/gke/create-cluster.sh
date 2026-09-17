#!/usr/bin/env bash
# Create a GKE Standard *zonal* cluster, spot first:
#   default-pool : removed after creation (GKE requires one at create time)
#   spot-cpu     : e2-standard-4 Spot VMs, autoscaling 1..3
#   spot-gpu     : g2-standard-4 + 1x NVIDIA L4 Spot VMs, autoscaling 0..1 (starts at 0 = $0)
# GPU driver is installed by GKE (gpu-driver-version=latest); details in 01-gpu-nodes-and-scheduling.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${PROJECT_ID:?}" "${ZONE:?}" "${GKE_CLUSTER:?}"

GPU_TYPE="${GPU_TYPE:-nvidia-l4}"            # or nvidia-tesla-t4 (use n1-standard-4)
GPU_MACHINE="${GPU_MACHINE:-g2-standard-4}"
CREATE_GPU_POOL="${CREATE_GPU_POOL:-true}"

gcloud config set project "$PROJECT_ID"
gcloud services enable container.googleapis.com

# Read-only check: is the accelerator offered in this zone?
if ! gcloud compute accelerator-types list --filter="zone:${ZONE} AND name:${GPU_TYPE}" \
      --format="value(name)" | grep -q "$GPU_TYPE"; then
  echo "WARNING: ${GPU_TYPE} not offered in ${ZONE}. Pick another ZONE (gcloud compute accelerator-types list --filter=name:${GPU_TYPE})."
fi

gcloud container clusters create "$GKE_CLUSTER" \
  --location "$ZONE" \
  --release-channel regular \
  --machine-type e2-standard-2 \
  --num-nodes 1 \
  --spot \
  --disk-type pd-balanced --disk-size 50 \
  --workload-pool "${PROJECT_ID}.svc.id.goog" \
  --enable-ip-alias

gcloud container node-pools create spot-cpu \
  --cluster "$GKE_CLUSTER" --location "$ZONE" \
  --machine-type e2-standard-4 \
  --spot \
  --num-nodes 1 \
  --enable-autoscaling --min-nodes 1 --max-nodes 3 \
  --disk-type pd-balanced --disk-size 50

# Remove the bootstrap pool now that spot-cpu exists.
gcloud container node-pools delete default-pool \
  --cluster "$GKE_CLUSTER" --location "$ZONE" --quiet

if [[ "$CREATE_GPU_POOL" == "true" ]]; then
  gcloud container node-pools create spot-gpu \
    --cluster "$GKE_CLUSTER" --location "$ZONE" \
    --machine-type "$GPU_MACHINE" \
    --accelerator "type=${GPU_TYPE},count=1,gpu-driver-version=latest" \
    --spot \
    --num-nodes 0 \
    --enable-autoscaling --min-nodes 0 --max-nodes 1 \
    --disk-type pd-balanced --disk-size 100
fi

gcloud container clusters get-credentials "$GKE_CLUSTER" --location "$ZONE"
kubectl get nodes -L cloud.google.com/gke-nodepool,cloud.google.com/gke-spot
