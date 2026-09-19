#!/usr/bin/env bash
# Cluster-side prerequisites for chapter 19 on AKS:
#   1. OIDC issuer + Workload Identity + Blob CSI driver on the cluster
#   2. spot CPU user pool "ch19spot" (WITH_ONDEMAND=true also adds an on-demand fallback at 0 nodes)
#   3. Argo Workflows with ch19-pipelines in controller.workflowNamespaces
#      (../common/install-argo-workflows.sh -- prints the GitOps alternative if ch15's Argo CD owns it)
# GPU capacity: the T4 "gpuspot" pool from 01-gpu-nodes-and-scheduling. Idempotent.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/versions.env"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AKS_CLUSTER:?}"

# --- 1. cluster features (skip the slow update when already on) ---
FEATURES="$(az aks show -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}" \
  --query '[oidcIssuerProfile.enabled, securityProfile.workloadIdentity.enabled, storageProfile.blobCsiDriver.enabled]' -o tsv | tr '\n\t' '  ' | tr '[:upper:]' '[:lower:]')"
# (az prints Python booleans in tsv output: "True", not "true" -- hence the lowercase.)
if [[ "${FEATURES}" != *"true true true"* ]]; then
  az aks update -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}" \
    --enable-oidc-issuer --enable-workload-identity --enable-blob-driver
fi

# --- 2. CPU spot pool (AKS adds the scalesetpriority=spot:NoSchedule taint automatically) ---
if az aks nodepool show -g "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" -n ch19spot >/dev/null 2>&1; then
  echo "node pool ch19spot already exists"
else
  az aks nodepool add -g "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" \
    --name ch19spot --mode User \
    --node-vm-size Standard_D4s_v5 \
    --priority Spot --eviction-policy Delete --spot-max-price -1 \
    --enable-cluster-autoscaler --min-count 0 --max-count 3 --node-count 1 \
    --node-osdisk-size 128 \
    --labels ai-lab/chapter=19
fi
if [[ "${WITH_ONDEMAND:-false}" == "true" ]] && \
   ! az aks nodepool show -g "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" -n ch19od >/dev/null 2>&1; then
  # On-demand fallback at 0 nodes. Pods select scalesetpriority=spot -- drop that from the patches to use it.
  az aks nodepool add -g "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" \
    --name ch19od --mode User --node-vm-size Standard_D4s_v5 \
    --enable-cluster-autoscaler --min-count 0 --max-count 2 --node-count 0 \
    --labels ai-lab/chapter=19 ai-lab/capacity=on-demand
fi

# --- 3. Argo Workflows ---
"${HERE}/../common/install-argo-workflows.sh"

cat <<NEXT

Next:
  ${HERE}/setup-blob-iam.sh    # storage account + managed identity + federated creds -> bucket.env
  ${HERE}/build-push-acr.sh    # trainer image -> ACR -> images.env
  kubectl apply -k ${HERE}
NEXT
