#!/usr/bin/env bash
# Create the EKS lab cluster from cluster.yaml (spot CPU pool + spot GPU pool at 0).
# NOTE: EKS has no node autoscaler by default. Scale the GPU group manually
# (01-gpu-nodes-and-scheduling/eks/scale-gpu-nodegroup.sh) or use Karpenter (13-node-autoscaling-and-cost).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AWS_REGION:?}" "${EKS_CLUSTER:?}"
export AWS_REGION EKS_CLUSTER

command -v envsubst >/dev/null || { echo "envsubst missing: brew install gettext"; exit 1; }
envsubst '${EKS_CLUSTER} ${AWS_REGION}' < "$HERE/cluster.yaml" > "$HERE/.cluster.rendered.yaml"

# --install-nvidia-plugin=false: eksctl would otherwise apply an unpinned device-plugin manifest.
# We install a pinned one via Helm in chapter 01 (or let the GPU Operator do it in chapter 02).
eksctl create cluster -f "$HERE/.cluster.rendered.yaml" --install-nvidia-plugin=false

kubectl get nodes -L eks.amazonaws.com/nodegroup,eks.amazonaws.com/capacityType,node.kubernetes.io/instance-type
