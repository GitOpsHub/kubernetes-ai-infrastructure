#!/usr/bin/env bash
# Enable Node Auto Provisioning on an existing AKS Standard cluster, then apply the
# AKSNodeClass/NodePool pair. NAP requires Azure CLI >= 2.76.0 and is incompatible with a Basic
# Load Balancer / Windows node pools / IPv6 clusters (see README "Troubleshooting").
#   ./enable-nap.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?}" "${AKS_CLUSTER:?}"

az aks update \
  --resource-group "$AZ_RESOURCE_GROUP" --name "$AKS_CLUSTER" \
  --node-provisioning-mode Auto

kubectl apply --server-side -f "$HERE/aksnodeclass.yaml"
kubectl apply --server-side -f "$HERE/nodepool.yaml"
kubectl get nodepools.karpenter.sh
echo "NAP enabled with gpu-spot (weight 10) + gpu-ondemand (weight 1) NodePools."
