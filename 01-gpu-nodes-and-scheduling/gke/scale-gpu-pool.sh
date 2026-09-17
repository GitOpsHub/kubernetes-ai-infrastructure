#!/usr/bin/env bash
# Pre-warm (NODES=1) or park (NODES=0) the GPU pool. The autoscaler also scales on Pending GPU pods.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${ZONE:?}" "${GKE_CLUSTER:?}"
POOL="${POOL:-spot-gpu}"; NODES="${NODES:-0}"
gcloud container clusters resize "$GKE_CLUSTER" --location "$ZONE" --node-pool "$POOL" --num-nodes "$NODES" --quiet
kubectl get nodes -l cloud.google.com/gke-nodepool="$POOL" -L cloud.google.com/gke-accelerator
