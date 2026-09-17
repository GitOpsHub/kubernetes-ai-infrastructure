#!/usr/bin/env bash
# GPU node pool for the NVIDIA DRA driver (GKE Standard, 1.35+; not supported on Autopilot).
# - gpu-driver-version=disabled: GKE does not auto-install drivers, we install them below.
# - gke-no-default-nvidia-gpu-device-plugin=true: GKE does NOT deploy its device plugin,
#   so the DRA driver is the only thing handing out these GPUs (never run both).
# - nvidia.com/gpu.present=true: the DRA kubelet plugin's nodeAffinity matches this label.
# - cloud.google.com/gke-nvidia-gpu-dra-driver=true: lets cluster autoscaler scale this pool
#   for pods with ResourceClaims.
set -euo pipefail
source "$(dirname "$0")/_common.sh"

POOL="${POOL:-l4-dra-spot}"

gcloud container node-pools create "${POOL}" \
  --project="${PROJECT_ID}" \
  --cluster="${GKE_CLUSTER}" \
  --location="${LOCATION}" \
  --node-locations="${NODE_ZONE}" \
  --machine-type=g2-standard-4 \
  --accelerator="type=nvidia-l4,count=1,gpu-driver-version=disabled" \
  --spot \
  --num-nodes=1 \
  --enable-autoscaling --min-nodes=0 --max-nodes=1 \
  --node-labels=course-chapter=03,gke-no-default-nvidia-gpu-device-plugin=true,nvidia.com/gpu.present=true,cloud.google.com/gke-nvidia-gpu-dra-driver=true

# ON-DEMAND FALLBACK: drop --spot.

# Install NVIDIA drivers on COS nodes (GKE's driver installer DaemonSet; it only
# schedules on nodes with cloud.google.com/gke-accelerator).
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded-latest.yaml
echo "Wait for: kubectl -n kube-system rollout status ds/nvidia-driver-installer"
