#!/usr/bin/env bash
set -euo pipefail
kubectl delete -k "$(dirname "${BASH_SOURCE[0]}")" --ignore-not-found
helm uninstall mlflow -n mlflow --ignore-not-found 2>/dev/null || true
helm uninstall argo-workflows -n argo --ignore-not-found 2>/dev/null || true
kubectl delete namespace argo mlflow --ignore-not-found
echo "ch15 cpu-lab: pipelines namespace, MLflow and Argo Workflows removed."
