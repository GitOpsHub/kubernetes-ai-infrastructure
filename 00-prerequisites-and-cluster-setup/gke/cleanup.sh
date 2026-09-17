#!/usr/bin/env bash
# Tear down. DELETE_CLUSTER=true removes the whole cluster; default only removes chapter workloads
# and scales GPU pool to 0.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${ZONE:?}" "${GKE_CLUSTER:?}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl delete -k "$HERE" --ignore-not-found || true
gcloud container clusters resize "$GKE_CLUSTER" --location "$ZONE" --node-pool spot-gpu --num-nodes 0 --quiet || true

if [[ "${DELETE_CLUSTER:-false}" == "true" ]]; then
  gcloud container clusters delete "$GKE_CLUSTER" --location "$ZONE" --quiet
  echo "Also check for orphaned disks: gcloud compute disks list --filter='-users:*'"
fi
