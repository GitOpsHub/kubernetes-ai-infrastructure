#!/usr/bin/env bash
# Create an AKS cluster, spot first:
#   system  : Regular priority (AKS does NOT allow the system/default pool to be Spot), 1 small node
#   spotcpu : Spot user pool, Standard_D4s_v5, autoscaling 0..3
#   gpuspot : Spot user pool, Standard_NC4as_T4_v3 (1x T4), autoscaling 0..1, starts at 0
# AKS auto-taints spot pools with kubernetes.azure.com/scalesetpriority=spot:NoSchedule.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?}" "${AZ_LOCATION:?}" "${AKS_CLUSTER:?}"
GPU_VM="${GPU_VM:-Standard_NC4as_T4_v3}"
CREATE_GPU_POOL="${CREATE_GPU_POOL:-true}"

az group create --name "$AZ_RESOURCE_GROUP" --location "$AZ_LOCATION" --tags project=k8s-ai-lab

az aks create \
  --resource-group "$AZ_RESOURCE_GROUP" --name "$AKS_CLUSTER" --location "$AZ_LOCATION" \
  --tier free \
  --nodepool-name system \
  --node-vm-size Standard_D2s_v5 \
  --node-count 1 \
  --enable-cluster-autoscaler --min-count 1 --max-count 2 \
  --network-plugin azure --network-plugin-mode overlay \
  --enable-oidc-issuer --enable-workload-identity \
  --generate-ssh-keys

az aks nodepool add \
  --resource-group "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" \
  --name spotcpu --mode User \
  --node-vm-size Standard_D4s_v5 \
  --priority Spot --eviction-policy Delete --spot-max-price -1 \
  --enable-cluster-autoscaler --node-count 1 --min-count 0 --max-count 3

if [[ "$CREATE_GPU_POOL" == "true" ]]; then
  # Default GPU profile on NVIDIA sizes = AKS installs the driver only (no device plugin).
  # The device plugin is installed in 01-gpu-nodes-and-scheduling/aks/install-device-plugin.sh.
  # Labels: nvidia.com/gpu.present=true lets the upstream device-plugin chart's default affinity match.
  az aks nodepool add \
    --resource-group "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" \
    --name gpuspot --mode User \
    --node-vm-size "$GPU_VM" \
    --priority Spot --eviction-policy Delete --spot-max-price -1 \
    --enable-cluster-autoscaler --node-count 0 --min-count 0 --max-count 1 \
    --node-taints "nvidia.com/gpu=present:NoSchedule" \
    --labels "nvidia.com/gpu.present=true" "workload=gpu"
fi

az aks get-credentials --resource-group "$AZ_RESOURCE_GROUP" --name "$AKS_CLUSTER" --overwrite-existing
kubectl get nodes -L agentpool,kubernetes.azure.com/scalesetpriority,node.kubernetes.io/instance-type
