#!/usr/bin/env bash
# For an EXISTING GKE Standard zonal cluster whose small nodes (e.g. 2x e2-medium spot) are full.
# Adds a bigger spot CPU pool that can scale to zero when idle. Does not touch existing pools.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${PROJECT_ID:?}" "${ZONE:?}" "${GKE_CLUSTER:?}"

POOL="${POOL:-spot-cpu-4}"
MACHINE="${MACHINE:-e2-standard-4}"   # 4 vCPU / 16 GiB
MAX_NODES="${MAX_NODES:-3}"

# Read-only: confirm the cluster is zonal Standard and show current pools
gcloud container clusters describe "$GKE_CLUSTER" --location "$ZONE" --project "$PROJECT_ID" \
  --format="table(name,location,autopilot.enabled,currentMasterVersion)"
gcloud container node-pools list --cluster "$GKE_CLUSTER" --location "$ZONE" --project "$PROJECT_ID"

# Cluster autoscaler is per node pool on GKE Standard; enabling it here is enough.
gcloud container node-pools create "$POOL" \
  --project "$PROJECT_ID" \
  --cluster "$GKE_CLUSTER" --location "$ZONE" \
  --machine-type "$MACHINE" \
  --spot \
  --num-nodes 1 \
  --enable-autoscaling --min-nodes 0 --max-nodes "$MAX_NODES" \
  --disk-type pd-balanced --disk-size 50

# Optional: let the autoscaler pack pods more aggressively so idle nodes go away sooner.
#   gcloud container clusters update "$GKE_CLUSTER" --location "$ZONE" \
#     --autoscaling-profile optimize-utilization
kubectl get nodes -L cloud.google.com/gke-nodepool,cloud.google.com/gke-spot,node.kubernetes.io/instance-type
