#!/usr/bin/env bash
# GPU node pool for the NVIDIA DRA driver on AKS (K8s 1.35+). --gpu-driver none: the GPU
# Operator (chapter 02) installs the driver so the DRA driver's kubeletPlugin can mount it
# from the operator's known path (see install-dra-driver.sh nvidiaDriverRoot).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?}" "${AKS_CLUSTER:?}"

GPU_VM="${GPU_VM:-Standard_NC4as_T4_v3}"
MAX_NODES="${MAX_NODES:-1}"

if [[ "${ON_DEMAND:-false}" == "true" ]]; then
  POOL="${POOL:-gpudraod}"; PRIORITY_FLAGS=()
else
  POOL="${POOL:-gpudra}";   PRIORITY_FLAGS=(--priority Spot --eviction-policy Delete --spot-max-price -1)
fi

az aks nodepool add \
  --resource-group "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" \
  --name "$POOL" --mode User \
  --node-vm-size "$GPU_VM" \
  ${PRIORITY_FLAGS[@]+"${PRIORITY_FLAGS[@]}"} \
  --gpu-driver none \
  --enable-cluster-autoscaler --node-count 0 --min-count 0 --max-count "$MAX_NODES" \
  --node-taints "nvidia.com/gpu=present:NoSchedule" \
  --labels "course-chapter=03" "gpu-mode=dra"

# ON-DEMAND FALLBACK: ON_DEMAND=true.
az aks nodepool show -g "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" -n "$POOL" \
  --query '{name:name,vm:vmSize,priority:scaleSetPriority,taints:nodeTaints,labels:nodeLabels}' -o json
