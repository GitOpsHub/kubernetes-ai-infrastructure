#!/usr/bin/env bash
# OpenCost against chapter 04's cpu-lab kube-prometheus-stack (fake DCGM exporter, real
# scrape/alert wiring). Cost numbers reflect OpenCost's default (no cloud billing) pricing model
# applied to fake/synthetic GPU utilization -- useful for learning the query shapes in README
# section 7, not for a real chargeback number.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${OPENCOST_CHART_VERSION:?source versions.env}"

if ! kubectl -n monitoring get svc kube-prometheus-stack-prometheus >/dev/null 2>&1; then
  echo "chapter 04's cpu-lab kube-prometheus-stack isn't installed (kubectl -n monitoring get svc" >&2
  echo "kube-prometheus-stack-prometheus failed) -- run 04-gpu-observability/cpu-lab first." >&2
  exit 1
fi

helm repo add opencost https://opencost.github.io/opencost-helm-chart --force-update
helm repo update opencost

helm upgrade --install opencost opencost/opencost \
  --namespace opencost --create-namespace \
  --version "${OPENCOST_CHART_VERSION}" \
  --set "opencost.prometheus.internal.enabled=false" \
  --set "opencost.prometheus.external.enabled=true" \
  --set-string "opencost.prometheus.external.url=http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/prometheus" \
  --wait --timeout 10m

kubectl apply -k "${HERE}/../common/opencost"

kubectl -n opencost get pods
echo
echo "UI:  kubectl -n opencost port-forward svc/opencost 9090:9090  ->  http://localhost:9090"
echo "What doesn't carry over: real cloud list-price GPU-hour costs (no cloud billing API here) --"
echo "only the scrape/query/alert wiring transfers to a real cluster, same caveat as chapter 04's"
echo "cpu-lab fake exporter."
