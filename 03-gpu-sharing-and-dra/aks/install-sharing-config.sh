#!/usr/bin/env bash
# Point the GPU Operator's device plugin at the sharing ConfigMap (time-slicing / MPS / MIG).
# Assumes the operator from chapter 02 is installed as release "gpu-operator" in ns gpu-operator.
# Identical mechanism to EKS - AKS has no cloud-native GPU sharing flag on az aks nodepool add.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/versions.env"
DIR="$(cd "$(dirname "$0")" && pwd)"

kubectl apply -k "${DIR}/../common/device-plugin-config"

helm upgrade gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --version "${GPU_OPERATOR_VERSION}" \
  --reuse-values \
  --set devicePlugin.config.name=device-plugin-sharing \
  --set devicePlugin.config.default=any \
  --set mig.strategy=single

kubectl get nodes -l course-chapter=03 \
  -o custom-columns='NAME:.metadata.name,CONFIG:.metadata.labels.nvidia\.com/device-plugin\.config,GPU:.status.allocatable.nvidia\.com/gpu'
