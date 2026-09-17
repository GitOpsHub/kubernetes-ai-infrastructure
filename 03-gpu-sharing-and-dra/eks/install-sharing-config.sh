#!/usr/bin/env bash
# Point the GPU Operator's device plugin at the sharing ConfigMap (time-slicing / MPS / MIG).
# Assumes the operator from chapter 02 is installed as release "gpu-operator" in ns gpu-operator.
set -euo pipefail
source "$(dirname "$0")/../../versions.env"
DIR="$(cd "$(dirname "$0")" && pwd)"

kubectl apply -k "${DIR}/../common/device-plugin-config"

helm upgrade gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --version "${GPU_OPERATOR_VERSION}" \
  --reuse-values \
  --set devicePlugin.config.name=device-plugin-sharing \
  --set devicePlugin.config.default=any \
  --set mig.strategy=single

# The operator's config-manager sidecar watches the node label and restarts the plugin itself.
# Change a node's profile at any time:
#   kubectl label node <node> nvidia.com/device-plugin.config=mps-4 --overwrite
kubectl get nodes -l course-chapter=03 \
  -o custom-columns='NAME:.metadata.name,CONFIG:.metadata.labels.nvidia\.com/device-plugin\.config,SHARING:.metadata.labels.nvidia\.com/gpu\.sharing-strategy,GPU:.status.allocatable.nvidia\.com/gpu'
