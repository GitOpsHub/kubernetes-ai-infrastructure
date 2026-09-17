#!/usr/bin/env bash
# Creates the checkpoint bucket, an IAM role for the Mountpoint for S3 CSI driver
# (IRSA, as in the AWS docs) and installs/updates the add-on so it tolerates the GPU taint.
# Then writes storage/storage.env for the kustomize overlay.
set -euo pipefail
: "${EKS_CLUSTER:?source env.sh}" "${AWS_REGION:?}" "${AWS_ACCOUNT_ID:?}"
BUCKET="${BUCKET:-${AWS_ACCOUNT_ID}-ch07-checkpoints}"
ROLE_NAME="${ROLE_NAME:-${EKS_CLUSTER}-s3-csi-driver}"
POLICY_NAME="${POLICY_NAME:-${EKS_CLUSTER}-ch07-s3-checkpoints}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if ! aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  fi
fi

POLICY_DOC=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid": "MountpointFullBucketAccess", "Effect": "Allow", "Action": ["s3:ListBucket"],
     "Resource": ["arn:aws:s3:::${BUCKET}"]},
    {"Sid": "MountpointFullObjectAccess", "Effect": "Allow",
     "Action": ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:DeleteObject"],
     "Resource": ["arn:aws:s3:::${BUCKET}/*"]}
  ]
}
JSON
)
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
aws iam get-policy --policy-arn "${POLICY_ARN}" >/dev/null 2>&1 || \
  aws iam create-policy --policy-name "${POLICY_NAME}" --policy-document "${POLICY_DOC}"

eksctl utils associate-iam-oidc-provider --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --approve
eksctl create iamserviceaccount \
  --name s3-csi-driver-sa --namespace kube-system \
  --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" \
  --attach-policy-arn "${POLICY_ARN}" \
  --role-name "${ROLE_NAME}" --role-only --approve

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
if aws eks describe-addon --cluster-name "${EKS_CLUSTER}" --addon-name aws-mountpoint-s3-csi-driver --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws eks update-addon --cluster-name "${EKS_CLUSTER}" --addon-name aws-mountpoint-s3-csi-driver \
    --region "${AWS_REGION}" --service-account-role-arn "${ROLE_ARN}" \
    --configuration-values '{"node":{"tolerateAllTaints":true}}' --resolve-conflicts OVERWRITE
else
  aws eks create-addon --cluster-name "${EKS_CLUSTER}" --addon-name aws-mountpoint-s3-csi-driver \
    --region "${AWS_REGION}" --service-account-role-arn "${ROLE_ARN}" \
    --configuration-values '{"node":{"tolerateAllTaints":true}}'
fi

printf 'BUCKET_NAME=%s\nMOUNT_REGION=region %s\n' "${BUCKET}" "${AWS_REGION}" > "${HERE}/storage/storage.env"
echo "Wrote ${HERE}/storage/storage.env"
