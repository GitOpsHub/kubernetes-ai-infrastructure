#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
source "$ROOT/versions.env"   # MLFLOW_CHART_VERSION: chart 1.11.7 == app 3.16.0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

helm repo add community-charts https://community-charts.github.io/helm-charts --force-update
helm repo update community-charts

helm upgrade --install mlflow community-charts/mlflow \
  --version "${MLFLOW_CHART_VERSION}" \
  --namespace mlflow --create-namespace \
  -f "$HERE/../common/mlflow/values-mlflow-cpu-lab.yaml"

kubectl -n mlflow rollout status deployment/mlflow --timeout=180s
echo "MLflow ${MLFLOW_CHART_VERSION} installed. UI: kubectl -n mlflow port-forward svc/mlflow 5000:5000"
