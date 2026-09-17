#!/usr/bin/env bash
set -euo pipefail
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AKS_CLUSTER:?}"

kubectl delete -k 06-batch-jobs-and-kueue/aks --ignore-not-found
kubectl delete -f 06-batch-jobs-and-kueue/common/jobs --ignore-not-found
helm uninstall kueue -n kueue-system || true
kubectl delete namespace kueue-system --ignore-not-found

az aks nodepool delete --resource-group "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" --name ch06spot --no-wait || true
az aks nodepool delete --resource-group "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" --name ch06ondemand --no-wait || true
