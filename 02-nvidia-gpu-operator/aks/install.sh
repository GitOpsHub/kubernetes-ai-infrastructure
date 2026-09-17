#!/usr/bin/env bash
# Install the NVIDIA GPU Operator on AKS via Helm, pinned to ${GPU_OPERATOR_VERSION}.
# Prereq: a GPU node pool created WITHOUT the AKS driver (az CLI >= 2.72.2):
#   GPU_DRIVER=none ../01-gpu-nodes-and-scheduling/aks/create-gpu-nodepool.sh
# Uninstall the standalone nvdp device-plugin release first if it's running:
#   helm -n nvidia-device-plugin uninstall nvdp
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
helm repo update nvidia

helm upgrade --install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --create-namespace \
  --version "${GPU_OPERATOR_VERSION}" \
  -f "$HERE/values-aks.yaml" \
  --wait --timeout 15m

kubectl -n gpu-operator get pods
echo "--- ClusterPolicy status (Ready when all operands come up) ---"
kubectl get clusterpolicy cluster-policy -o jsonpath='{.status.state}{"\n"}'
