#!/usr/bin/env bash
set -euo pipefail
: "${EKS_CLUSTER:?source env.sh}" "${AWS_REGION:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"

kubectl delete rayservices,rayjobs,rayclusters --all -n ch08-ray --ignore-not-found
kubectl delete -k "${HERE}" --ignore-not-found || true
for ng in ch08-gpu-spot-l4 ch08-gpu-ondemand-l4; do
  eksctl delete nodegroup --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --name "${ng}" --wait 2>/dev/null || true
done
if [[ "${UNINSTALL_OPERATOR:-false}" == "true" ]]; then
  helm uninstall kuberay-operator -n kuberay-system || true
fi
