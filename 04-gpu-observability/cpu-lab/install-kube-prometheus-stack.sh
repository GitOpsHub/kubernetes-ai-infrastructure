#!/usr/bin/env bash
# kube-prometheus-stack with no cloud-specific nodeSelector/storageClass - works on any cluster
# with a default StorageClass (kind, minikube, a plain CPU-only cloud cluster).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update prometheus-community

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --version "${KUBE_PROMETHEUS_STACK_VERSION}" \
  --set prometheus.prometheusSpec.retention=1d \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=true \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=true \
  --set grafana.sidecar.dashboards.enabled=true \
  --set grafana.sidecar.dashboards.searchNamespace=ALL \
  --wait --timeout 15m

kubectl apply -k "$HERE"
kubectl apply -k "$HERE/../common/servicemonitor"
kubectl apply -k "$HERE/../common/alerts"
kubectl apply -k "$HERE/../common/dashboards"

kubectl -n monitoring get pods
echo "Grafana:    kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80"
echo "Prometheus: kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
