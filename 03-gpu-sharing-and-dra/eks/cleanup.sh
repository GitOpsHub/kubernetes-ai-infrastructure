#!/usr/bin/env bash
set -euo pipefail
: "${EKS_CLUSTER:?source env.sh}" "${AWS_REGION:?source env.sh}"
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

for ng in gpu-share-spot gpu-dra-spot gpu-mig-spot; do
  eksctl delete nodegroup --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --name "${ng}" --wait=false 2>/dev/null || true
done
rm -f "${DIR}/.nodegroups.rendered.yaml"
