#!/usr/bin/env bash
# Confirm Gateway API is available on the cluster (Standard clusters on a recent release
# channel have it on by default; explicitly enabling costs nothing if already on).
#   ./create-gateway.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${PROJECT_ID:?}" "${GKE_CLUSTER:?}" "${ZONE:?}"

gcloud container clusters update "$GKE_CLUSTER" --location "$ZONE" --project "$PROJECT_ID" \
  --gateway-api=standard

echo "GatewayClasses available on this cluster:"
kubectl get gatewayclass
