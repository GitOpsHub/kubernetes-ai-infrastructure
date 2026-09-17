#!/usr/bin/env bash
# Install the NVIDIA GPU Operator on GKE via Helm, pinned to ${GPU_OPERATOR_VERSION}.
# Prereq: a spot GPU node pool created with the GKE driver installer disabled, e.g.
#   GPU_DRIVER_VERSION=disabled ../01-gpu-nodes-and-scheduling/gke/create-gpu-nodepool.sh
# If you already installed the chapter 01 device plugin on this cluster, uninstall it first
# (../01-gpu-nodes-and-scheduling/gke/cleanup.sh with UNINSTALL_PLUGIN unset does NOT remove it;
# run `helm -n nvidia-device-plugin uninstall nvdp` explicitly) — do not run two device plugins.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
helm repo update nvidia

helm upgrade --install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --create-namespace \
  --version "${GPU_OPERATOR_VERSION}" \
  -f "$HERE/values-gke.yaml" \
  --wait --timeout 15m

kubectl -n gpu-operator get pods
echo "--- ClusterPolicy status (Ready when all operands come up) ---"
kubectl get clusterpolicy cluster-policy -o jsonpath='{.status.state}{"\n"}'
