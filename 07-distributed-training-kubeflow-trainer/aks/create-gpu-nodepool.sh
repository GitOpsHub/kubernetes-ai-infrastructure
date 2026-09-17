#!/usr/bin/env bash
# Spot T4 GPU node pool that scales from zero. 2 nodes x 1 T4 for the 2-node DDP lab.
# Same shape as 01-gpu-nodes-and-scheduling/aks/create-gpu-nodepool.sh: AKS installs the NVIDIA
# driver itself (--gpu-driver Install) and we taint/label the pool ourselves (AKS does NOT
# auto-taint GPU pools the way it auto-taints spot pools).
# Requires a Standard_NCASv3_T4 family vCPU quota (spot: "Standard NCASv3_T4 Family vCPUs",
# on-demand: the non-spot equivalent) >= 8 in ${AZ_LOCATION}.
set -euo pipefail
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AKS_CLUSTER:?}"
GPU_VM="${GPU_VM:-Standard_NC4as_T4_v3}"
CAPACITY="${CAPACITY:-spot}"              # CAPACITY=on-demand for the fallback pool

if [[ "${CAPACITY}" == "spot" ]]; then
  POOL="${POOL:-gpuspot}"
  PRIORITY_FLAGS=(--priority Spot --eviction-policy Delete --spot-max-price -1)
else
  POOL="${POOL:-gpuondemand}"
  PRIORITY_FLAGS=()
fi

az aks nodepool add \
  --resource-group "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" \
  --name "${POOL}" --mode User \
  --node-vm-size "${GPU_VM}" \
  "${PRIORITY_FLAGS[@]+"${PRIORITY_FLAGS[@]}"}" \
  --gpu-driver Install \
  --enable-cluster-autoscaler --node-count 0 --min-count 0 --max-count 2 \
  --node-taints "nvidia.com/gpu=present:NoSchedule" \
  --labels "nvidia.com/gpu.present=true" "ch07.lab/pool=${POOL}"

az aks nodepool show -g "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" -n "${POOL}" \
  --query '{name:name,vm:vmSize,priority:scaleSetPriority,taints:nodeTaints,labels:nodeLabels}' -o json
