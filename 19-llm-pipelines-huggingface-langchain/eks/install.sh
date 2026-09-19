#!/usr/bin/env bash
# Cluster-side prerequisites for chapter 19 on EKS:
#   1. the CPU spot managed node group "ch19-cpu-spot" (nodegroup-ch19.yaml)
#   2. Argo Workflows with ch19-pipelines in controller.workflowNamespaces
#      (../common/install-argo-workflows.sh -- prints the GitOps alternative if ch15's Argo CD owns it)
# GPU capacity comes from 01-gpu-nodes-and-scheduling (spot-gpu node group + device plugin).
# Idempotent. INCLUDE=ch19-cpu-ondemand also creates the on-demand fallback group.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/versions.env"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AWS_REGION:?source env.sh}" "${EKS_CLUSTER:?}"
export AWS_REGION EKS_CLUSTER
INCLUDE="${INCLUDE:-ch19-cpu-spot}"

# --- 1. CPU spot node group ---
if eksctl get nodegroup --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --name "${INCLUDE%%,*}" >/dev/null 2>&1; then
  echo "node group ${INCLUDE%%,*} already exists"
else
  TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT    # rendered copy stays out of the repo
  RENDERED="${TMP}/nodegroup-ch19.yaml"
  # shellcheck disable=SC2016  # literal ${VARS} for envsubst
  envsubst '${EKS_CLUSTER} ${AWS_REGION}' < "${HERE}/nodegroup-ch19.yaml" > "${RENDERED}"
  eksctl create nodegroup -f "${RENDERED}" --include "${INCLUDE}"
fi

# --- 2. Argo Workflows ---
"${HERE}/../common/install-argo-workflows.sh"

cat <<NEXT

Next:
  ${HERE}/setup-s3-iam.sh        # bucket + Pod Identity + Mountpoint CSI add-on -> bucket.env
  ${HERE}/build-push-ecr.sh      # trainer image -> ECR -> images.env
  kubectl apply -k ${HERE}
NEXT
