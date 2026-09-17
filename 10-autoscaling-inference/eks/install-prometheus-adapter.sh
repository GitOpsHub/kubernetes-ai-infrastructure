#!/usr/bin/env bash
# Install prometheus-adapter (custom.metrics.k8s.io, feeds the HPA in ../common/hpa) and KEDA
# (feeds the ScaledObject in ../common/keda). Prereq: 04-gpu-observability's kube-prometheus-stack
# already running in-cluster (namespace "monitoring").
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update prometheus-community

helm upgrade --install prometheus-adapter prometheus-community/prometheus-adapter \
  --namespace monitoring --create-namespace \
  --version "${PROMETHEUS_ADAPTER_VERSION}" \
  -f "$HERE/../common/values-prometheus-adapter.yaml" \
  --wait --timeout 5m

kubectl get apiservice v1beta1.custom.metrics.k8s.io
echo "List: kubectl get --raw '/apis/custom.metrics.k8s.io/v1beta1' | jq"
