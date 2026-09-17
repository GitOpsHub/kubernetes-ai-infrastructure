#!/usr/bin/env bash
# Two CPU node pools for the chapter-06 Kueue labs. AKS taints Spot node pools automatically with
# kubernetes.azure.com/scalesetpriority=spot:NoSchedule, which is why the "spot" ResourceFlavor
# needs BOTH nodeLabels and tolerations (see aks/kustomization.yaml) - Kueue's classic
# nodeSelector-only flavors aren't enough here.
set -euo pipefail
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AKS_CLUSTER:?}"

az aks nodepool add \
  --resource-group "${AZ_RESOURCE_GROUP}" \
  --cluster-name "${AKS_CLUSTER}" \
  --name ch06spot \
  --mode User \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --node-vm-size Standard_D4as_v5 \
  --node-count 1 \
  --min-count 0 --max-count 3 --enable-cluster-autoscaler \
  --labels workload=ch06-batch

az aks nodepool add \
  --resource-group "${AZ_RESOURCE_GROUP}" \
  --cluster-name "${AKS_CLUSTER}" \
  --name ch06ondemand \
  --mode User \
  --node-vm-size Standard_D4as_v5 \
  --node-count 1 \
  --min-count 0 --max-count 1 --enable-cluster-autoscaler \
  --labels workload=ch06-controller

az aks nodepool list --resource-group "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" -o table
