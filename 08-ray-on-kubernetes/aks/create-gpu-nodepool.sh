#!/usr/bin/env bash
# Spot T4 GPU node pool for the Ray worker group only. AKS installs the NVIDIA driver itself
# (--gpu-driver Install) and, unlike its automatic spot taint, does NOT auto-taint GPU pools --
# we taint/label it ourselves (same shape as 07-distributed-training-kubeflow-trainer/aks).
# Requires a "Standard NCASv3_T4 Family vCPUs" (spot) quota >= 8 in ${AZ_LOCATION}.
set -euo pipefail
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AKS_CLUSTER:?}"
GPU_VM="${GPU_VM:-Standard_NC4as_T4_v3}"
CAPACITY="${CAPACITY:-spot}"

if [[ "${CAPACITY}" == "spot" ]]; then
  POOL="${POOL:-ch08gpuspot}"
  PRIORITY_FLAGS=(--priority Spot --eviction-policy Delete --spot-max-price -1)
else
  POOL="${POOL:-ch08gpuod}"
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
  --labels "nvidia.com/gpu.present=true" "ch08.lab/pool=${POOL}"

az aks nodepool show -g "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" -n "${POOL}" \
  --query '{name:name,vm:vmSize,priority:scaleSetPriority,taints:nodeTaints,labels:nodeLabels}' -o json
