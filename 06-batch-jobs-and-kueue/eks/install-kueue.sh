#!/usr/bin/env bash
# Installs Kueue via the official OCI Helm chart, pinned to ${KUEUE_VERSION}.
# The controller is pinned to the on-demand nodegroup (eks.amazonaws.com/capacityType=ON_DEMAND)
# so a spot reclaim never takes the scheduler itself down.
set -euo pipefail
: "${KUEUE_VERSION:?source versions.env}"
HERE="$(cd "$(dirname "$0")" && pwd)"

helm install kueue oci://registry.k8s.io/kueue/charts/kueue \
  --version "${KUEUE_VERSION}" \
  --namespace kueue-system --create-namespace \
  -f "${HERE}/../common/values-kueue.yaml" \
  --set 'controllerManager.nodeSelector.eks\.amazonaws\.com/capacityType=ON_DEMAND' \
  --wait --timeout 5m

kubectl -n kueue-system rollout status deploy/kueue-controller-manager --timeout=5m
kubectl get crd | grep kueue.x-k8s.io
