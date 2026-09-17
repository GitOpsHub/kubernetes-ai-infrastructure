#!/usr/bin/env bash
# Deletes lab workloads and GPU node groups. Keeps bucket/IAM unless DELETE_BUCKET=true.
set -euo pipefail
: "${EKS_CLUSTER:?source env.sh}" "${AWS_REGION:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"

kubectl delete trainjobs --all -n ch07-training --ignore-not-found
kubectl delete -k "${HERE}" --ignore-not-found || true
for ng in gpu-spot-l4 gpu-ondemand-l4; do
  eksctl delete nodegroup --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --name "${ng}" --wait 2>/dev/null || true
done
if [[ "${UNINSTALL_TRAINER:-false}" == "true" ]]; then
  helm uninstall kubeflow-trainer -n kubeflow-system || true
fi
if [[ "${DELETE_BUCKET:-false}" == "true" ]]; then
  aws s3 rb "s3://${BUCKET:-${AWS_ACCOUNT_ID}-ch07-checkpoints}" --force
fi
