#!/usr/bin/env bash
# EKS has no autoscaler by default: NODES=1 to start a GPU node, NODES=0 to stop paying.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AWS_REGION:?}" "${EKS_CLUSTER:?}"
NG="${NG:-spot-gpu}"; NODES="${NODES:-0}"
eksctl scale nodegroup --cluster "$EKS_CLUSTER" --region "$AWS_REGION" --name "$NG" \
  --nodes "$NODES" --nodes-min 0 --nodes-max "$(( NODES > 1 ? NODES : 1 ))"
kubectl get nodes -l eks.amazonaws.com/nodegroup="$NG" -L node.kubernetes.io/instance-type,eks.amazonaws.com/capacityType
