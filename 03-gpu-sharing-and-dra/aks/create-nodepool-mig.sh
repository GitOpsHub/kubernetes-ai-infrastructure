#!/usr/bin/env bash
# ADVANCED / EXPENSIVE: AKS-native MIG via --gpu-instance-profile (self-managed driver path).
# Only A100 / H100 / H200 series VMs support MIG on AKS. Standard_ND96asr_v4 = 8x A100 40GB;
# the profile applies to every GPU in the node and CANNOT be changed after creation
# (delete and recreate the pool to change it).
# Verified against: https://learn.microsoft.com/azure/aks/gpu-multi-instance (2026-05-22).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?}" "${AKS_CLUSTER:?}"

GPU_VM="${GPU_VM:-Standard_ND96asr_v4}"
PROFILE="${PROFILE:-MIG1g}"   # MIG1g | MIG2g | MIG3g | MIG4g | MIG7g - immutable once set

if [[ "${ON_DEMAND:-false}" == "true" ]]; then
  POOL="${POOL:-gpumigod}"; PRIORITY_FLAGS=()
else
  POOL="${POOL:-gpumig}";   PRIORITY_FLAGS=(--priority Spot --eviction-policy Delete --spot-max-price -1)
fi

az aks nodepool add \
  --resource-group "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" \
  --name "$POOL" --mode User \
  --node-vm-size "$GPU_VM" \
  --node-count 0 \
  ${PRIORITY_FLAGS[@]+"${PRIORITY_FLAGS[@]}"} \
  --gpu-driver Install \
  --gpu-instance-profile "$PROFILE" \
  --enable-cluster-autoscaler --min-count 0 --max-count 1 \
  --node-taints "nvidia.com/gpu=present:NoSchedule" \
  --labels "course-chapter=03" "nvidia.com/device-plugin.config=mig-single"

# ON-DEMAND FALLBACK: ON_DEMAND=true. Spot capacity for ND-series A100/H100 is scarce; if the
# create hangs on AllocationFailed, fall back to on-demand or try another region.
# After the pool is Ready, install the NVIDIA device plugin + GFD with MIG_STRATEGY=single
# (see README) - AKS's own driver install does NOT deploy a device plugin for you.
az aks nodepool show -g "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" -n "$POOL" \
  --query '{name:name,vm:vmSize,priority:scaleSetPriority,gpuProfile:gpuInstanceProfile,taints:nodeTaints}' -o json
