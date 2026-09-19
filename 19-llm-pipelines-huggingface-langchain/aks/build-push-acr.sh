#!/usr/bin/env bash
# Build the ch19-trainer image (GPU torch, CUDA 12.9 wheels) for linux/amd64, push it to an Azure
# Container Registry, let the cluster pull from it (--attach-acr = AcrPull for the kubelet
# identity), and write images.env.
# ACR names are global and alphanumeric: derived from subscription + cluster so re-runs reuse it.
#   TAG=v2 ./build-push-acr.sh          (default tag: current git commit)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AZ_LOCATION:?}" "${AKS_CLUSTER:?}" "${AZ_SUBSCRIPTION_ID:?}"

ACR_NAME="${AZ_ACR_NAME:-ch19acr$(printf '%s' "${AZ_SUBSCRIPTION_ID}${AKS_CLUSTER}" | shasum | cut -c1-12)}"
TAG="${TAG:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || date -u +%Y%m%d%H%M)}"
CONTEXT="${HERE}/../common/src/trainer"

if ! az acr show -n "${ACR_NAME}" -g "${AZ_RESOURCE_GROUP}" >/dev/null 2>&1; then
  az acr create -n "${ACR_NAME}" -g "${AZ_RESOURCE_GROUP}" -l "${AZ_LOCATION}" --sku Basic >/dev/null
fi
LOGIN_SERVER="$(az acr show -n "${ACR_NAME}" -g "${AZ_RESOURCE_GROUP}" --query loginServer -o tsv)"
IMAGE="${LOGIN_SERVER}/ch19-trainer:${TAG}"
# Grants AcrPull to the cluster's kubelet identity (no imagePullSecrets needed). Re-run safe.
az aks update -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}" --attach-acr "${ACR_NAME}" >/dev/null
az acr login -n "${ACR_NAME}"

# --platform: AKS GPU nodes are x86_64 (an Apple-silicon build would be arm64 -> exec format error).
docker buildx build --platform linux/amd64 \
  --build-arg TORCH_VARIANT=cu129 \
  -t "${IMAGE}" --push "${CONTEXT}"

printf '# written by build-push-acr.sh\nTRAINER_IMAGE=%s\n' "${IMAGE}" > "${HERE}/images.env"
echo "pushed ${IMAGE}; ${HERE}/images.env updated"
