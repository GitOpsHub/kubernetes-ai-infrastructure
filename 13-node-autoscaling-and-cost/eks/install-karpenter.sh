#!/usr/bin/env bash
# Install the Karpenter controller (Helm, pinned from versions.env) and apply the
# EC2NodeClass/NodePool pair (cluster-scoped, so applied directly here rather than via
# `kubectl apply -k`, after envsubst fills in ${EKS_CLUSTER}).
#
# Assumes the Karpenter IAM role/instance profile + SQS interruption queue already exist --
# out of scope for a manifests-only chapter; see the Karpenter EKS getting-started guide (README
# "Further reading") for `eksctl create iamserviceaccount` / CloudFormation prerequisites, or use
# `karpenter-provider-aws`'s `cloudformation.yaml` template. This script assumes that's done and
# the role is named `KarpenterNodeRole-${EKS_CLUSTER}` (matches ec2nodeclass.yaml).
#   ./install-karpenter.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${EKS_CLUSTER:?}" "${AWS_REGION:?}" "${AWS_ACCOUNT_ID:?}"

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "$KARPENTER_VERSION" \
  --namespace kube-system \
  --set settings.clusterName="$EKS_CLUSTER" \
  --set settings.interruptionQueue="$EKS_CLUSTER" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --wait --timeout 5m

echo "Applying EC2NodeClass + NodePool (spot-first, on-demand fallback)..."
envsubst < "$HERE/ec2nodeclass.yaml" | kubectl apply --server-side -f -
envsubst < "$HERE/nodepool.yaml"     | kubectl apply --server-side -f -

kubectl get nodepools.karpenter.sh
echo "Karpenter ${KARPENTER_VERSION} installed with gpu-spot (weight 10) + gpu-ondemand (weight 1)."
