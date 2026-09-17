#!/usr/bin/env bash
# Default: remove chapter workloads and scale GPU group to 0. DELETE_CLUSTER=true deletes everything
# (control plane costs ~USD 0.10/h even with zero nodes).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AWS_REGION:?}" "${EKS_CLUSTER:?}"

kubectl delete -k "$HERE" --ignore-not-found || true
eksctl scale nodegroup --cluster "$EKS_CLUSTER" --region "$AWS_REGION" --name spot-gpu --nodes 0 --nodes-min 0 || true

if [[ "${DELETE_CLUSTER:-false}" == "true" ]]; then
  eksctl delete cluster --name "$EKS_CLUSTER" --region "$AWS_REGION" --wait
  echo "Check for leftover EBS volumes / load balancers in ${AWS_REGION}."
fi
