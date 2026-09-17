#!/usr/bin/env bash
# Delete everything chapter 03 created on AKS. GPU node pools bill per second - run this.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?}" "${AKS_CLUSTER:?}"
DIR="$(cd "$(dirname "$0")" && pwd)"

for k in timeslicing mps mig dra; do
  kubectl delete -k "${DIR}/${k}" --ignore-not-found --wait=false || true
done
helm uninstall nvidia-dra-driver-gpu -n nvidia-dra-driver-gpu 2>/dev/null || true
kubectl delete namespace nvidia-dra-driver-gpu --ignore-not-found --wait=false
kubectl delete -k "${DIR}/../common/device-plugin-config" --ignore-not-found || true
# Revert the operator to its default (no sharing config):
#   helm upgrade gpu-operator nvidia/gpu-operator -n gpu-operator --reuse-values \
#     --set devicePlugin.config.name="" --set devicePlugin.config.default=""

for pool in gpushare gpumig gpudra; do
  az aks nodepool delete -g "$AZ_RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER" -n "$pool" 2>/dev/null || true
done
