#!/usr/bin/env bash
# Install KEDA, pinned to ${KEDA_VERSION}. Same chart/values on every cloud — no GKE-specific
# values needed (KEDA talks to Prometheus over HTTP, not through a cloud metrics API here).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/versions.env"

helm repo add kedacore https://kedacore.github.io/charts --force-update
helm repo update kedacore

helm upgrade --install keda kedacore/keda \
  --namespace keda --create-namespace \
  --version "${KEDA_VERSION}" \
  --wait --timeout 5m

kubectl -n keda get pods
