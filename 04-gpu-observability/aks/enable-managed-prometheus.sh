#!/usr/bin/env bash
# ALTERNATIVE to kube-prometheus-stack: Azure Monitor managed service for Prometheus + Container
# Insights, both fully managed (no Prometheus/Alertmanager pods to run). Trade-off: dcgm-exporter
# metrics still need a scrape target definition (Azure Monitor's default config does not know
# about dcgm-exporter), and viewing them needs an Azure Managed Grafana workspace linked to the
# Azure Monitor workspace. CREATES BILLED AZURE RESOURCES. Not run by this course.
# Verified flags: https://learn.microsoft.com/azure/azure-monitor/containers/kubernetes-monitoring-enable
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?}" "${AKS_CLUSTER:?}"

# Managed Prometheus metrics (creates a default Azure Monitor workspace if none given/found):
az aks update --enable-azure-monitor-metrics \
  --name "$AKS_CLUSTER" --resource-group "$AZ_RESOURCE_GROUP"

# Container Insights (logs + the classic container metrics, separate add-on from Managed Prometheus):
az aks enable-addons --addon monitoring \
  --name "$AKS_CLUSTER" --resource-group "$AZ_RESOURCE_GROUP"

# Optional: control-plane (apiserver/etcd/scheduler) metrics into the same workspace.
az aks update --enable-control-plane-metrics \
  --name "$AKS_CLUSTER" --resource-group "$AZ_RESOURCE_GROUP"

# Custom scrape targets (dcgm-exporter) need an ama-metrics-prometheus-config ConfigMap; see
# https://learn.microsoft.com/azure/azure-monitor/containers/prometheus-metrics-scrape-configuration
echo "Next: link an Azure Managed Grafana workspace to the Azure Monitor workspace to view metrics."
