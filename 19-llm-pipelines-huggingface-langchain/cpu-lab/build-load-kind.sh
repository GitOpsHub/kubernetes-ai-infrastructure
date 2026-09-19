#!/usr/bin/env bash
# Build the CPU-torch trainer image locally and load it straight into the cluster's nodes -- no
# registry. kind by default (KIND_CLUSTER=<name>, default "kind"); minikube if the current
# kubectl context is "minikube". Other clusters: push ch19-trainer:cpu to a registry the nodes can
# pull from and put that reference in images.env.
# Built for the host's own architecture (no --platform): kind/minikube nodes run on this machine,
# and torch publishes CPU wheels for both amd64 and arm64.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-ch19-trainer:cpu}"
CONTEXT="${HERE}/../common/src/trainer"

docker build --build-arg TORCH_VARIANT=cpu -t "${IMAGE}" "${CONTEXT}"

CONTEXT_NAME="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${CONTEXT_NAME}" == "minikube" ]]; then
  minikube image load "${IMAGE}"
else
  kind load docker-image "${IMAGE}" --name "${KIND_CLUSTER:-kind}"
fi

printf '# written by build-load-kind.sh\nTRAINER_IMAGE=%s\n' "${IMAGE}" > "${HERE}/images.env"
echo "loaded ${IMAGE} into ${CONTEXT_NAME:-the cluster}; ${HERE}/images.env updated"
