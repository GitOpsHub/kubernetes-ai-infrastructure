#!/usr/bin/env bash
# Create an AKS GPU node pool, spot by default, scale-from-zero via cluster autoscaler.
#   GPU_VM=Standard_NC4as_T4_v3 (default, 1x T4) | Standard_NV36ads_A10_v5 | Standard_NC24ads_A100_v4 (advanced)
#   ON_DEMAND=true   -> Regular priority pool "gpuod" (needs per-family vCPU quota)
#   GPU_DRIVER=Install (default: AKS installs the NVIDIA driver) | None (bring your own, e.g. GPU Operator, chapter 02)
# AKS default for NVIDIA sizes = driver only: you must install a device plugin (install-device-plugin.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?}" "${AKS_CLUSTER:?}"
GPU_VM="${GPU_VM:-Standard_NC4as_T4_v3}"
GPU_DRIVER="${GPU_DRIVER:-Install}"
MAX_NODES="${MAX_NODES:-1}"

if [[ "${ON_DEMAND:-false}" == "true" ]]; then
  POOL="${POOL:-gpuod}";   PRIORITY_FLAGS=()
else
  POOL="${POOL:-gpuspot}"; PRIORITY_FLAGS=(--priority Spot --eviction-policy Delete --spot-max-price -1)
fi

az aks nodepool add \
  --resource-group "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" \
  --name "$POOL" --mode User \
  --node-vm-size "$GPU_VM" \
  ${PRIORITY_FLAGS[@]+"${PRIORITY_FLAGS[@]}"} \
  --gpu-driver "$GPU_DRIVER" \
  --enable-cluster-autoscaler --node-count 0 --min-count 0 --max-count "$MAX_NODES" \
  --node-taints "nvidia.com/gpu=present:NoSchedule" \
  --labels "nvidia.com/gpu.present=true" "workload=gpu"

az aks nodepool show -g "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" -n "$POOL" \
  --query '{name:name,vm:vmSize,priority:scaleSetPriority,gpuProfile:gpuProfile,taints:nodeTaints,labels:nodeLabels}' -o json
