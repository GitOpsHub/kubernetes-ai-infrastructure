#!/usr/bin/env bash
# Remove chapter workloads; DELETE_POOL=true also deletes the GPU node pool.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${ZONE:?}" "${GKE_CLUSTER:?}"
kubectl delete -k "$HERE" --ignore-not-found || true
if [[ "${DELETE_POOL:-false}" == "true" ]]; then
  gcloud container node-pools delete "${POOL:-spot-gpu}" --cluster "$GKE_CLUSTER" --location "$ZONE" --quiet
fi
