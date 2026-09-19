#!/usr/bin/env bash
# Chapter 02 has no meaningful CPU-only hands-on lab: the Operator's entire job is installing a real
# GPU driver, container toolkit and DCGM stack, none of which exist on a CPU node. What you CAN do
# without a cluster, a cloud account, or a GPU is validate that the chart renders correctly for
# values-eks.yaml and that our ClusterPolicy mirror matches. Everything here is local/offline:
# `helm template`/`helm lint` render client-side, and `kubectl kustomize` never contacts a cluster.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update >/dev/null
helm repo update nvidia >/dev/null

echo "== helm template (rendered, not applied): eks =="
helm template gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --version "${GPU_OPERATOR_VERSION}" \
  -f "$HERE/../eks/values-eks.yaml" \
  --show-only templates/clusterpolicy.yaml

echo "== kubectl kustomize (our mirrored ClusterPolicy): eks =="
kubectl kustomize "$HERE/../eks" >/dev/null && echo "OK: eks overlay builds"

echo "== kubectl kustomize: common =="
kubectl kustomize "$HERE/../common" >/dev/null && echo "OK: common builds"
