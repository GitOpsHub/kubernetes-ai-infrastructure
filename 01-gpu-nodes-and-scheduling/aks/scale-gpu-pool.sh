#!/usr/bin/env bash
# Pre-warm: MIN=1 forces one GPU node; MIN=0 lets the autoscaler remove it when idle.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?}" "${AKS_CLUSTER:?}"
POOL="${POOL:-gpuspot}"; MIN="${MIN:-0}"; MAX="${MAX:-1}"
az aks nodepool update -g "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" -n "$POOL" \
  --update-cluster-autoscaler --min-count "$MIN" --max-count "$MAX"
kubectl get nodes -l agentpool="$POOL" -L node.kubernetes.io/instance-type,kubernetes.azure.com/scalesetpriority
