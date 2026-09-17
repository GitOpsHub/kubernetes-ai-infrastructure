#!/usr/bin/env bash
# Enable Node Auto-Provisioning (NAP) with resource limits (NAP will refuse to create nodes past
# these, an important cost guardrail). Cluster Autoscaler is on by default for any node pool
# created with --enable-autoscaling; NAP additionally creates/removes whole NODE POOLS for you
# based on ComputeClasses/pending Pod shapes.
#   ./enable-nap.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${PROJECT_ID:?}" "${GKE_CLUSTER:?}" "${ZONE:?}"

gcloud container clusters update "$GKE_CLUSTER" --location "$ZONE" --project "$PROJECT_ID" \
  --enable-autoprovisioning \
  --min-cpu 0 --min-memory 0 \
  --max-cpu 32 --max-memory 128 \
  --autoprovisioning-max-surge-upgrade 1 --autoprovisioning-max-unavailable-upgrade 0

echo "NAP enabled. GPU limits for autoprovisioned pools are set via --autoprovisioning-locations" \
     "and per-accelerator quota; also apply computeclass.yaml (kubectl apply -k gke) so NAP knows" \
     "the spot-first/flex-start preference for GPU Pods."
