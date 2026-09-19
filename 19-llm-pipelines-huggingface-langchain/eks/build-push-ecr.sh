#!/usr/bin/env bash
# Build the ch19-trainer image (GPU torch, CUDA 12.9 wheels) for linux/amd64 and push it to ECR,
# then write images.env so `kubectl apply -k` injects the exact tag into the WorkflowTemplate.
# The image is large (~6-8 GB: torch + CUDA libs); expect the first push and the first pull on
# each new spot GPU node to take a few minutes.
#   TAG=v2 ./build-push-ecr.sh         (default tag: current git commit)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AWS_REGION:?source env.sh}" "${AWS_ACCOUNT_ID:?}"

REPO=ch19-trainer
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
TAG="${TAG:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || date -u +%Y%m%d%H%M)}"
IMAGE="${REGISTRY}/${REPO}:${TAG}"
CONTEXT="${HERE}/../common/src/trainer"

if ! aws ecr describe-repositories --repository-names "${REPO}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws ecr create-repository --repository-name "${REPO}" --region "${AWS_REGION}" \
    --image-scanning-configuration scanOnPush=true >/dev/null
fi
# Every rebuild pushes another ~6-8 GB image, and ECR bills per GB-month: keep only the newest 5.
aws ecr put-lifecycle-policy --repository-name "${REPO}" --region "${AWS_REGION}" \
  --lifecycle-policy-text '{"rules":[{"rulePriority":1,"description":"keep last 5 images","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":5},"action":{"type":"expire"}}]}' \
  >/dev/null
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${REGISTRY}"

# --platform: EKS GPU nodes are x86_64; building on an Apple-silicon laptop would otherwise
# produce an arm64 image that fails with "exec format error" on the node.
docker buildx build --platform linux/amd64 \
  --build-arg TORCH_VARIANT=cu129 \
  -t "${IMAGE}" --push "${CONTEXT}"

printf '# written by build-push-ecr.sh\nTRAINER_IMAGE=%s\n' "${IMAGE}" > "${HERE}/images.env"
echo "pushed ${IMAGE}; ${HERE}/images.env updated"
