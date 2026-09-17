#!/usr/bin/env bash
# Installs Kueue via the official OCI Helm chart, pinned to ${KUEUE_VERSION}. No node-pool
# targeting here - cpu-lab assumes a single-pool cluster (kind/minikube, or any one spot CPU
# pool you already have).
set -euo pipefail
: "${KUEUE_VERSION:?source versions.env}"
HERE="$(cd "$(dirname "$0")" && pwd)"

helm install kueue oci://registry.k8s.io/kueue/charts/kueue \
  --version "${KUEUE_VERSION}" \
  --namespace kueue-system --create-namespace \
  -f "${HERE}/../common/values-kueue.yaml" \
  --wait --timeout 5m

kubectl -n kueue-system rollout status deploy/kueue-controller-manager --timeout=5m
kubectl get crd | grep kueue.x-k8s.io
