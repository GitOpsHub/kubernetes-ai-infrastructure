#!/usr/bin/env bash
# Default: delete the chapter's Kubernetes objects (Workflows, WorkflowTemplates, Deployments,
# PV/PVC, namespace) and scale the ch19 CPU node groups to 0. The bucket, IAM roles, Pod Identity
# associations, ECR repository and node groups are KEPT (the bucket holds your models/checkpoints).
#   DELETE_CLOUD_RESOURCES=true ./cleanup.sh   -> also delete all of those (bucket contents too!)
# Argo Workflows is shared with chapter 15 and is left installed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AWS_REGION:?source env.sh}" "${EKS_CLUSTER:?}"
# shellcheck disable=SC1091
source "${HERE}/bucket.env"
NS=ch19-pipelines

# Workflow objects first so their pods go before the PVC they mount.
kubectl -n "${NS}" delete workflows.argoproj.io --all --ignore-not-found 2>/dev/null || true
kubectl delete -k "${HERE}" --ignore-not-found || true

for ng in ch19-cpu-spot ch19-cpu-ondemand; do
  eksctl scale nodegroup --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --name "${ng}" \
    --nodes 0 --nodes-min 0 2>/dev/null || true
done
echo "GPU capacity is 01's spot-gpu group: ../../01-gpu-nodes-and-scheduling/eks/cleanup.sh scales it to 0."

if [[ "${DELETE_CLOUD_RESOURCES:-false}" != "true" ]]; then
  echo "KEPT: s3://${S3_BUCKET}, IAM roles ch19-*-${EKS_CLUSTER}, ECR repo ch19-trainer, node groups ch19-cpu-*."
  echo "      Re-run with DELETE_CLOUD_RESOURCES=true to delete them (S3 storage + ECR storage bill monthly)."
  exit 0
fi

echo "DELETE_CLOUD_RESOURCES=true: deleting Pod Identity associations, IAM roles, bucket, ECR repo, node groups"
for id in $(aws eks list-pod-identity-associations --cluster-name "${EKS_CLUSTER}" --region "${AWS_REGION}" \
      --namespace "${NS}" --query 'associations[].associationId' --output text); do
  aws eks delete-pod-identity-association --cluster-name "${EKS_CLUSTER}" --region "${AWS_REGION}" --association-id "${id}" >/dev/null
done
for sa in pipeline-runner model-reader; do
  ROLE="ch19-${sa}-${EKS_CLUSTER}"
  aws iam delete-role-policy --role-name "${ROLE}" --policy-name s3-ch19 2>/dev/null || true
  aws iam delete-role --role-name "${ROLE}" 2>/dev/null || true
done
if aws s3api head-bucket --bucket "${S3_BUCKET}" 2>/dev/null; then
  aws s3 rm "s3://${S3_BUCKET}" --recursive
  aws s3api delete-bucket --bucket "${S3_BUCKET}" --region "${AWS_REGION}"
fi
aws ecr delete-repository --repository-name ch19-trainer --region "${AWS_REGION}" --force >/dev/null 2>&1 || true
for ng in ch19-cpu-spot ch19-cpu-ondemand; do
  eksctl delete nodegroup --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --name "${ng}" 2>/dev/null || true
done
echo "ch19 EKS cloud resources deleted. (Mountpoint / Pod Identity add-ons left: other chapters use them.)"
