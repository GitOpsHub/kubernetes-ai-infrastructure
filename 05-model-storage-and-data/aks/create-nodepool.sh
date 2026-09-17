#!/usr/bin/env bash
# Spot user node pool for chapter 05 + cluster features the lab needs
# (OIDC issuer, Workload Identity, Blob CSI driver).
set -euo pipefail
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AKS_CLUSTER:?}"

az aks update -g "${AZ_RESOURCE_GROUP}" -n "${AKS_CLUSTER}" \
  --enable-oidc-issuer --enable-workload-identity --enable-blob-driver

# Spot first (AKS adds the kubernetes.azure.com/scalesetpriority=spot:NoSchedule taint automatically).
# D-series v5 = Intel Ice Lake with AVX-512 for the vLLM CPU backend.
az aks nodepool add -g "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" \
  --name ch05spot \
  --mode User \
  --node-vm-size Standard_D8s_v5 \
  --priority Spot --eviction-policy Delete --spot-max-price -1 \
  --enable-cluster-autoscaler --min-count 0 --max-count 2 --node-count 1 \
  --node-osdisk-size 128

# On-demand fallback, scaled to zero until needed.
if [[ "${WITH_ONDEMAND:-false}" == "true" ]]; then
  az aks nodepool add -g "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" \
    --name ch05od --mode User --node-vm-size Standard_D8s_v5 \
    --enable-cluster-autoscaler --min-count 0 --max-count 2 --node-count 0 \
    --labels ai-lab/capacity=on-demand
fi
