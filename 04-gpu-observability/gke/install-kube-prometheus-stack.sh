#!/usr/bin/env bash
# Install kube-prometheus-stack on GKE, pinned to ${KUBE_PROMETHEUS_STACK_VERSION}.
# Release name "kube-prometheus-stack" matters: common/servicemonitor and common/alerts carry
# label release=kube-prometheus-stack for the chart's default selector to find them.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update prometheus-community

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --version "${KUBE_PROMETHEUS_STACK_VERSION}" \
  -f "$HERE/values-kube-prometheus-stack.yaml" \
  --wait --timeout 15m

kubectl apply -k "$HERE/../common/servicemonitor"
kubectl apply -k "$HERE/../common/alerts"
kubectl apply -k "$HERE/../common/dashboards"

kubectl -n monitoring get pods
echo "Grafana: kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80"
echo "Prometheus targets: kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
