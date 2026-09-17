#!/usr/bin/env bash
# AKS GPU node pool for time-slicing / MPS via the GPU Operator's device plugin
# (chapter 02). AKS has no GKE-style --gpu-sharing-strategy flag on az aks nodepool add;
# sharing is entirely a device-plugin-config concern, same as EKS. --gpu-driver none because
# the GPU Operator (chapter 02) installs and owns the driver.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?}" "${AKS_CLUSTER:?}"

GPU_VM="${GPU_VM:-Standard_NC4as_T4_v3}"   # T4; Standard_NV36ads_A10_v5 (A10) also supports sharing
MAX_NODES="${MAX_NODES:-1}"
SHARE_MODE="${SHARE_MODE:-time-sliced-4}"  # key in common/device-plugin-config: time-sliced-4 | mps-4

if [[ "${ON_DEMAND:-false}" == "true" ]]; then
  POOL="${POOL:-gpushareod}"; PRIORITY_FLAGS=()
else
  POOL="${POOL:-gpushare}";   PRIORITY_FLAGS=(--priority Spot --eviction-policy Delete --spot-max-price -1)
fi

az aks nodepool add \
  --resource-group "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" \
  --name "$POOL" --mode User \
  --node-vm-size "$GPU_VM" \
  ${PRIORITY_FLAGS[@]+"${PRIORITY_FLAGS[@]}"} \
  --gpu-driver none \
  --enable-cluster-autoscaler --node-count 0 --min-count 0 --max-count "$MAX_NODES" \
  --node-taints "nvidia.com/gpu=present:NoSchedule" \
  --labels "course-chapter=03" "nvidia.com/device-plugin.config=${SHARE_MODE}"

# ON-DEMAND FALLBACK: ON_DEMAND=true (drops Spot priority flags, needs per-family vCPU quota).
az aks nodepool show -g "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" -n "$POOL" \
  --query '{name:name,vm:vmSize,priority:scaleSetPriority,taints:nodeTaints,labels:nodeLabels}' -o json
