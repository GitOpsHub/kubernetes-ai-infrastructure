#!/usr/bin/env bash
# Pattern (e) on GKE: preload the (huge) vLLM image – or model data – onto a secondary boot disk
# so new spot nodes start with it already on disk. Reference script; read the README section first.
set -euo pipefail
: "${PROJECT_ID:?source env.sh}" "${REGION:?}" "${ZONE:?}" "${GKE_CLUSTER:?}"
source "$(cd "$(dirname "$0")/../.." && pwd)/versions.env"

DISK_IMAGE="${DISK_IMAGE:-vllm-cache-$(echo "${VLLM_VERSION}" | tr '.' '-')}"
LOG_BUCKET="${LOG_BUCKET:-${PROJECT_ID}-disk-image-builder-logs}"

cat <<MSG
Step 1 – build the disk image with gke-disk-image-builder (Go tool in GoogleCloudPlatform/ai-on-gke):
  git clone https://github.com/GoogleCloudPlatform/ai-on-gke && cd ai-on-gke/tools/gke-disk-image-builder
  gcloud storage buckets create gs://${LOG_BUCKET} --location ${REGION}
  go run ./cli \\
    --project-name=${PROJECT_ID} \\
    --image-name=${DISK_IMAGE} \\
    --zone=${ZONE} \\
    --gcs-path=gs://${LOG_BUCKET} \\
    --disk-size-gb=50 \\
    --container-image=docker.io/vllm/vllm-openai:${VLLM_VERSION}
MSG

read -r -p "Image ${DISK_IMAGE} built? Create the node pool now? [y/N] " ok
[[ "${ok}" == "y" ]] || exit 0

# Step 2 – node pool that mounts it as a container image cache (requires image streaming).
gcloud container node-pools create ch05-preloaded-spot \
  --project "${PROJECT_ID}" \
  --cluster "${GKE_CLUSTER}" \
  --location "${REGION}" \
  --machine-type n2-standard-8 \
  --spot \
  --num-nodes 0 --enable-autoscaling --min-nodes 0 --max-nodes 2 \
  --enable-image-streaming \
  --secondary-boot-disk "disk-image=global/images/${DISK_IMAGE},mode=CONTAINER_IMAGE_CACHE"
