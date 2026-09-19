#!/usr/bin/env bash
# Build the ch19-trainer image (GPU torch, CUDA 12.9 wheels) for linux/amd64, push it to an
# Artifact Registry repo in the cluster's region, and write images.env.
# Nodes pull with the node service account: it needs roles/artifactregistry.reader on the repo
# (the default compute SA has it; a least-privilege node SA from chapter 00 may not).
#   TAG=v2 ./build-push-artifact-registry.sh       (default tag: current git commit)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${PROJECT_ID:?source env.sh}" "${REGION:?}"

AR_REPO="${AR_REPO:-ch19}"
REGISTRY="${REGION}-docker.pkg.dev"
TAG="${TAG:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || date -u +%Y%m%d%H%M)}"
IMAGE="${REGISTRY}/${PROJECT_ID}/${AR_REPO}/ch19-trainer:${TAG}"
CONTEXT="${HERE}/../common/src/trainer"

if ! gcloud artifacts repositories describe "${AR_REPO}" --location "${REGION}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud artifacts repositories create "${AR_REPO}" --repository-format docker \
    --location "${REGION}" --project "${PROJECT_ID}" --description "chapter 19 images"
fi
gcloud auth configure-docker "${REGISTRY}" --quiet

# --platform: GKE GPU nodes are x86_64 (an Apple-silicon build would be arm64 -> exec format error).
docker buildx build --platform linux/amd64 \
  --build-arg TORCH_VARIANT=cu129 \
  -t "${IMAGE}" --push "${CONTEXT}"

printf '# written by build-push-artifact-registry.sh\nTRAINER_IMAGE=%s\n' "${IMAGE}" > "${HERE}/images.env"
echo "pushed ${IMAGE}; ${HERE}/images.env updated"
