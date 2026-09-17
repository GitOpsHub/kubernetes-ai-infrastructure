#!/usr/bin/env bash
set -euo pipefail
: "${AWS_REGION:?source env.sh}" "${EKS_CLUSTER:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/bucket.env"

kubectl delete -k "${HERE}/shared-fs" --ignore-not-found || true
kubectl delete -k "${HERE}" --ignore-not-found || true

for id in $(aws eks list-pod-identity-associations --cluster-name "${EKS_CLUSTER}" --region "${AWS_REGION}" \
      --namespace ch05-models --query 'associations[].associationId' --output text); do
  aws eks delete-pod-identity-association --cluster-name "${EKS_CLUSTER}" --region "${AWS_REGION}" --association-id "${id}"
done
for who in reader writer; do
  ROLE="ch05-model-${who}-${EKS_CLUSTER}"
  aws iam delete-role-policy --role-name "${ROLE}" --policy-name s3-models || true
  aws iam delete-role --role-name "${ROLE}" || true
done

if [[ "${DELETE_BUCKET:-false}" == "true" ]]; then
  aws s3 rm "s3://${S3_BUCKET}" --recursive
  aws s3api delete-bucket --bucket "${S3_BUCKET}" --region "${AWS_REGION}"
fi

eksctl delete nodegroup --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --name ch05-cpu-spot || true
eksctl delete nodegroup --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --name ch05-cpu-ondemand || true
echo "EFS file system (if created by shared-fs/setup-efs.sh) is NOT deleted automatically – see shared-fs/setup-efs.sh header."
