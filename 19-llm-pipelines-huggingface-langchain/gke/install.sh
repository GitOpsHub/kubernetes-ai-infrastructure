#!/usr/bin/env bash
# Cluster-side prerequisites for chapter 19 on GKE:
#   1. Cloud Storage FUSE CSI driver add-on (opt-in on Standard clusters)
#   2. spot CPU node pool "ch19-cpu-spot" (SPOT=false -> on-demand fallback)
#   3. Argo Workflows with ch19-pipelines in controller.workflowNamespaces
#      (../common/install-argo-workflows.sh -- prints the GitOps alternative if ch15's Argo CD owns it)
# GPU capacity: the L4 spot pool from 01-gpu-nodes-and-scheduling. Idempotent.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/versions.env"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${PROJECT_ID:?source env.sh}" "${ZONE:?}" "${GKE_CLUSTER:?}"
# Chapter 00 creates a ZONAL cluster (--location "$ZONE"); --location REGION would not find it.
GKE_LOCATION="${GKE_LOCATION:-${ZONE}}"
POOL="${POOL:-ch19-cpu-spot}"

# --- 1. GCS FUSE CSI driver ---
ENABLED="$(gcloud container clusters describe "${GKE_CLUSTER}" --project "${PROJECT_ID}" --location "${GKE_LOCATION}" \
  --format 'value(addonsConfig.gcsFuseCsiDriverConfig.enabled)')"
if [[ "${ENABLED}" != "True" ]]; then
  gcloud container clusters update "${GKE_CLUSTER}" --project "${PROJECT_ID}" --location "${GKE_LOCATION}" \
    --update-addons GcsFuseCsiDriver=ENABLED
fi

# --- 2. CPU node pool (spot first) ---
# (${arr[@]+...} form: macOS bash 3.2 treats an empty array as unset under `set -u`)
SPOT_FLAG=(--spot)
[[ "${SPOT:-true}" == "false" ]] && SPOT_FLAG=()
if gcloud container node-pools describe "${POOL}" --cluster "${GKE_CLUSTER}" \
     --location "${GKE_LOCATION}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  echo "node pool ${POOL} already exists"
else
  gcloud container node-pools create "${POOL}" \
    --project "${PROJECT_ID}" --cluster "${GKE_CLUSTER}" --location "${GKE_LOCATION}" \
    --machine-type e2-standard-4 \
    ${SPOT_FLAG[@]+"${SPOT_FLAG[@]}"} \
    --num-nodes 1 \
    --enable-autoscaling --min-nodes 0 --max-nodes 3 \
    --disk-type pd-balanced --disk-size 100 \
    --workload-metadata GKE_METADATA \
    --node-labels ai-lab/chapter=19
fi

# --- 3. Argo Workflows ---
"${HERE}/../common/install-argo-workflows.sh"

cat <<NEXT

Next:
  ${HERE}/setup-gcs-iam.sh                 # bucket + IAM for the KSAs -> bucket.env
  ${HERE}/build-push-artifact-registry.sh  # trainer image -> Artifact Registry -> images.env
  kubectl apply -k ${HERE}
NEXT
