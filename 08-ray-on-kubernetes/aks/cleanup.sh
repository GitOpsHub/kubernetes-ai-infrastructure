#!/usr/bin/env bash
set -euo pipefail
: "${AZ_RESOURCE_GROUP:?source env.sh}" "${AKS_CLUSTER:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"

kubectl delete rayservices,rayjobs,rayclusters --all -n ch08-ray --ignore-not-found
kubectl delete -k "${HERE}" --ignore-not-found || true
for pool in ch08gpuspot ch08gpuod; do
  az aks nodepool delete -g "${AZ_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER}" -n "${pool}" --no-wait 2>/dev/null || true
done
if [[ "${UNINSTALL_OPERATOR:-false}" == "true" ]]; then
  helm uninstall kuberay-operator -n kuberay-system || true
fi
