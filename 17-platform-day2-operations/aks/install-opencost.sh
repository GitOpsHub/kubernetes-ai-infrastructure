#!/usr/bin/env bash
# Install OpenCost for per-team/per-GPU-hour chargeback reporting, pointed at chapter 04's
# existing kube-prometheus-stack (must already be installed: 04-gpu-observability/aks).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${OPENCOST_CHART_VERSION:?source versions.env}"

if ! kubectl -n monitoring get svc kube-prometheus-stack-prometheus >/dev/null 2>&1; then
  echo "chapter 04's kube-prometheus-stack isn't installed (kubectl -n monitoring get svc" >&2
  echo "kube-prometheus-stack-prometheus failed) -- run 04-gpu-observability/aks first." >&2
  exit 1
fi

helm repo add opencost https://opencost.github.io/opencost-helm-chart --force-update
helm repo update opencost

helm upgrade --install opencost opencost/opencost \
  --namespace opencost --create-namespace \
  --version "${OPENCOST_CHART_VERSION}" \
  -f "${HERE}/values-opencost-aks.yaml" \
  --wait --timeout 10m

kubectl apply -k "${HERE}/../common/opencost"

kubectl -n opencost get pods
echo
echo "UI:  kubectl -n opencost port-forward svc/opencost 9090:9090  ->  http://localhost:9090"
echo "API: curl 'http://localhost:9090/allocation/compute?window=1d&aggregate=namespace' | jq"
echo "See README section 7 for the GPU-hour-per-team query and the idle-GPU alert this wires up."
